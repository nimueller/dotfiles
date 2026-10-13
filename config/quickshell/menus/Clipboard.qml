import QtQuick
import QtQuick.Controls as Controls // only the scroll bar; its Label would shadow ours
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Clipboard history (cliphist), part of daemon.qml so SUPER+V opens it at
// once: the key sends the Hyprland event "quickshell-clipboard";
// `toggle.sh clipboard` does the same from scripts. Type to filter, ↑/↓ to
// move, Enter or a click pastes the entry into the window you came from
// (copied, then Ctrl+V; Ctrl+Shift+V in terminals); Shift+Delete removes it.
// Images show as thumbnails: each is decoded once, when its row first shows,
// into ~/.cache/quickshell-clipboard (files of removed entries are pruned).
PanelWindow {
    id: root

    readonly property int rows: 9
    readonly property int rowHeight: 40
    readonly property int imageRowHeight: 88
    readonly property string cacheDir: `${Quickshell.env("HOME")}/.cache/quickshell-clipboard`

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

    // Copy the entry, then paste it into the window that gets the focus back
    // once the picker is gone (paste.sh). Works for images too.
    function pick(entry) {
        if (!entry)
            return;
        hide();
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" | cliphist decode | "$2"', "sh", entry.line, Quickshell.shellPath("paste.sh")]);
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
                        info: image ? `${image[2]} · ${image[1]}` : "",
                        file: image ? `${root.cacheDir}/${line.slice(0, tab)}.${image[2]}` : ""
                    };
                });
                // Drop decoded images whose entries are gone
                const keep = root.entries.filter(e => e.image).map(e => e.file.split("/").pop()).join(" ");
                Quickshell.execDetached(["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in *; do case " $2 " in *" $f "*) ;; *) rm -f -- "$f" ;; esac; done', "sh", root.cacheDir, keep]);
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

                    // Draggable bar for long histories
                    Controls.ScrollBar.vertical: Controls.ScrollBar {
                        id: scrollBar
                        policy: Controls.ScrollBar.AsNeeded
                        width: 12
                        rightPadding: 3

                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: scrollBar.pressed ? Theme.lavender : scrollBar.hovered ? Theme.overlay1 : Theme.alpha(Theme.overlay1, 0.5)

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        background: Item {}
                    }

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
                        height: modelData.image ? root.imageRowHeight : root.rowHeight

                        // Decode the image into the cache (once) when the row shows
                        Process {
                            id: decode
                            command: ["sh", "-c", 'mkdir -p "$(dirname "$2")"; [ -s "$2" ] || { printf "%s\\n" "$1" | cliphist decode > "$2.part" && mv "$2.part" "$2"; }', "sh", row.modelData.line, row.modelData.file]
                            onExited: code => {
                                if (code === 0)
                                    thumbnail.source = `file://${row.modelData.file}`;
                            }
                        }
                        Component.onCompleted: {
                            if (modelData.image)
                                decode.running = true;
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 24
                            spacing: 12

                            Label {
                                visible: !row.modelData.image
                                Layout.preferredWidth: 18
                                text: Theme.glyph(0xf0147) // 󰅇
                                color: row.current ? Theme.lavender : Theme.overlay1
                            }

                            // Thumbnail (the image glyph until it's decoded)
                            Rectangle {
                                visible: row.modelData.image
                                Layout.preferredWidth: 128
                                Layout.preferredHeight: 72
                                radius: 6
                                color: Theme.surface0
                                border.width: row.current ? 1 : 0
                                border.color: Theme.lavender

                                Image {
                                    id: thumbnail
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    sourceSize.height: 144
                                }
                                Label {
                                    anchors.centerIn: parent
                                    visible: thumbnail.status !== Image.Ready
                                    text: Theme.glyph(0xf02e9) // 󰋩
                                    font.pixelSize: 20
                                    color: Theme.overlay1
                                }
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
