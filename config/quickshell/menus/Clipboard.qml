import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Clipboard history (cliphist), part of daemon.qml so SUPER+V opens it at
// once: the key sends the Hyprland event "quickshell-clipboard";
// `toggle.sh clipboard` does the same from scripts. Type to filter, ↑/↓ to
// move, Enter or a click copies the entry and, for text, types it into the
// focused window (like the old rofi picker); Shift+Delete removes an entry.
PanelWindow {
    id: root

    readonly property int rows: 9
    readonly property int rowHeight: 40

    property bool shown: false
    property var entries: [] // { line, id, text, image, info }
    property string query: ""
    property bool confirmWipe: false

    readonly property var results: {
        const q = query.trim().toLowerCase();
        return q ? entries.filter(e => e.text.toLowerCase().includes(q)) : entries;
    }

    function show() {
        search.text = "";
        confirmWipe = false;
        load.running = true;
        list.positionViewAtBeginning();
        shown = true;
        search.forceActiveFocus();
    }

    function hide() {
        shown = false;
    }

    function toggle() {
        if (shown)
            hide();
        else
            show();
    }

    // Copy the entry; text is also typed into the window that gets the focus
    // back once the picker is gone
    function pick(entry) {
        if (!entry)
            return;
        hide();
        const copy = 'printf "%s\\n" "$1" | cliphist decode | wl-copy';
        const type = 'sleep 0.2; printf "%s\\n" "$1" | cliphist decode | wtype -';
        Quickshell.execDetached(["sh", "-c", entry.image ? copy : `${copy} && ${type}`, "sh", entry.line]);
    }

    function remove(entry) {
        if (!entry)
            return;
        edit.command = ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "sh", entry.line];
        edit.running = true;
    }

    function wipe() {
        edit.command = ["cliphist", "wipe"];
        edit.running = true;
        confirmWipe = false;
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            root.toggle();
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "custom" && event.data === "quickshell-clipboard")
                root.toggle();
        }
    }

    // `cliphist list`: "<id>\t<preview>", newest first; images read
    // "[[ binary data 224 KiB png 1920x1080 ]]"
    Process {
        id: load
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l.includes("\t")).map(line => {
                    const tab = line.indexOf("\t");
                    const preview = line.slice(tab + 1);
                    const image = preview.match(/^\[\[ binary data (.+) (\w+) (\d+x\d+) \]\]$/);
                    return {
                        line,
                        id: line.slice(0, tab),
                        text: image ? `Image ${image[3]}` : preview,
                        image: !!image,
                        info: image ? `${image[2]} · ${image[1]}` : ""
                    };
                });
            }
        }
    }

    Process {
        id: edit
        onExited: load.running = true
    }

    visible: shown
    implicitWidth: 640
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    HyprlandFocusGrab {
        active: root.shown
        windows: [root]
        onCleared: root.hide()
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: content.implicitHeight
        radius: 14
        color: Theme.base
        border.width: 1
        border.color: Theme.surface0

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: content

            width: parent.width
            spacing: 0

            // Search field and "clear all"
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: 18
                Layout.rightMargin: 14
                spacing: 12

                Label {
                    text: Theme.glyph(0xf014e) // 󰅎
                    font.pixelSize: 18
                    color: Theme.lavender
                }

                TextInput {
                    id: search

                    Layout.fillWidth: true
                    focus: true
                    color: Theme.text
                    selectionColor: Theme.alpha(Theme.lavender, 0.35)
                    selectedTextColor: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                    clip: true
                    onTextChanged: {
                        root.query = text;
                        list.currentIndex = 0;
                    }

                    Label {
                        visible: !search.text
                        text: "Search the clipboard history…"
                        font.pixelSize: 15
                        color: Theme.overlay0
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Escape)
                            root.hide();
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N)))
                            list.incrementCurrentIndex();
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P)))
                            list.decrementCurrentIndex();
                        else if (event.key === Qt.Key_PageDown)
                            list.currentIndex = Math.min(list.count - 1, list.currentIndex + root.rows);
                        else if (event.key === Qt.Key_PageUp)
                            list.currentIndex = Math.max(0, list.currentIndex - root.rows);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.pick(root.results[list.currentIndex]);
                        else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier))
                            root.remove(root.results[list.currentIndex]);
                        else
                            return;
                        event.accepted = true;
                    }
                }

                IconButton {
                    visible: root.entries.length > 0
                    glyph: Theme.glyph(0xf05e9) // 󰗩
                    text: root.confirmWipe ? "Really clear?" : "Clear"
                    accent: Theme.red
                    active: root.confirmWipe
                    onClicked: {
                        if (root.confirmWipe)
                            root.wipe();
                        else
                            root.confirmWipe = true;
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.surface0
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.rows * root.rowHeight + 16

                Label {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    text: root.entries.length ? "Nothing matches" : "The clipboard history is empty"
                    color: Theme.overlay0
                    font.italic: true
                }

                ListView {
                    id: list

                    anchors.fill: parent
                    topMargin: 8
                    bottomMargin: 8
                    clip: true
                    model: root.results
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 80
                    keyNavigationWraps: true

                    highlight: Item {
                        width: list.width

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            radius: 10
                            color: Theme.alpha(Theme.lavender, 0.14)
                        }
                    }

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool current: ListView.isCurrentItem

                        width: list.width
                        height: root.rowHeight

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 12

                            Label {
                                Layout.preferredWidth: 18
                                text: Theme.glyph(row.modelData.image ? 0xf02e9 : 0xf0147) // 󰋩 / 󰅇
                                color: row.current ? Theme.lavender : Theme.overlay1
                            }
                            Label {
                                Layout.fillWidth: true
                                // One line: show line breaks as ⏎
                                text: row.modelData.text.replace(/\s*\n\s*/g, " ⏎ ")
                                font.pixelSize: 13
                                color: row.current ? Theme.text : Theme.subtext1
                            }
                            Label {
                                visible: !!row.modelData.info
                                text: row.modelData.info
                                font.pixelSize: 10
                                color: Theme.overlay0
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: list.currentIndex = row.index
                            onClicked: root.pick(row.modelData)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.surface0
            }
            Label {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                horizontalAlignment: Text.AlignHCenter
                text: "↑↓  select     ⏎  paste     shift+del  remove     esc  close"
                font.pixelSize: 10
                color: Theme.overlay0
            }
        }
    }
}
