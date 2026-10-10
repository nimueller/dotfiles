import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// App launcher. Type to filter, ↑/↓ (or Ctrl+J/K, Tab) to move, Enter to
// launch. Apps you launch often float to the top. The last row runs the text
// as a command ("ssh host" opens in a terminal).
PanelWindow {
    id: root

    readonly property int rows: 8
    readonly property int rowHeight: 52
    readonly property string historyPath: `${Quickshell.env("HOME")}/.local/state/quickshell-launcher.json`

    property string query: ""
    property var counts: ({}) // launches per desktop entry id

    readonly property var apps: {
        const seen = new Set();
        return DesktopEntries.applications.values.filter(a => {
            if (a.noDisplay || seen.has(a.name))
                return false;
            seen.add(a.name);
            return true;
        });
    }
    readonly property var results: {
        const q = query.trim().toLowerCase();
        const ranked = apps.map(app => ({ app, score: score(app, q) })).filter(r => r.score >= 0);
        ranked.sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name));
        const list = ranked.map(r => r.app);
        if (q)
            list.push({ run: query.trim() });
        return list;
    }

    function score(app, q) {
        const used = Math.min(counts[app.id] ?? 0, 50) * 4;
        if (!q)
            return used;
        const name = app.name.toLowerCase();
        const extra = `${app.genericName} ${app.keywords} ${app.comment} ${app.categories}`.toLowerCase();
        let s = -1;
        if (name === q)
            s = 1000;
        else if (name.startsWith(q))
            s = 800;
        else if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            s = 600;
        else if (name.includes(q))
            s = 400;
        else if (`${app.genericName} ${app.keywords}`.toLowerCase().includes(q))
            s = 250;
        else if (initials(name).startsWith(q))
            s = 150;
        else if (extra.includes(q))
            s = 100;
        return s < 0 ? -1 : s + used;
    }

    // "visual studio code" -> "vsc"
    function initials(name) {
        return name.split(/[\s\-_.:]+/).map(w => w[0] ?? "").join("");
    }

    function launch(item) {
        if (!item)
            return;
        if (item.run !== undefined) {
            const ssh = item.run.startsWith("ssh ");
            Quickshell.execDetached(ssh ? ["xdg-terminal-exec", "sh", "-c", item.run] : ["sh", "-c", item.run]);
            Qt.quit();
            return;
        }
        if (item.runInTerminal) {
            const cmd = typeof item.command === "string" ? ["sh", "-c", item.command] : Array.from(item.command);
            Quickshell.execDetached(["xdg-terminal-exec", ...cmd]);
        } else {
            item.execute();
        }
        counts[item.id] = (counts[item.id] ?? 0) + 1;
        store.setText(JSON.stringify(counts));
        quitTimer.start();
    }

    // Launch counts survive restarts. Quit once they're written (or after a
    // short fallback) so a launch is never lost.
    FileView {
        id: store
        path: root.historyPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                root.counts = JSON.parse(text());
            } catch (e) {}
        }
        onSaved: Qt.quit()
    }
    Timer {
        id: quitTimer
        interval: 400
        onTriggered: Qt.quit()
    }

    implicitWidth: 560
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    HyprlandFocusGrab {
        active: true
        windows: [root]
        onCleared: Qt.quit()
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: content.implicitHeight
        radius: 14
        color: Theme.base
        border.width: 1
        border.color: Theme.surface0

        opacity: 0
        scale: 0.97
        Component.onCompleted: {
            opacity = 1;
            scale = 1;
        }
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: content

            width: parent.width
            spacing: 0

            // Search field
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                spacing: 12

                Label {
                    text: Theme.glyph(0xf0349) // 󰍉
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
                        text: "Search apps…"
                        font.pixelSize: 15
                        color: Theme.overlay0
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Escape)
                            Qt.quit();
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N)))
                            list.incrementCurrentIndex();
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P)))
                            list.decrementCurrentIndex();
                        else if (event.key === Qt.Key_PageDown)
                            list.currentIndex = Math.min(list.count - 1, list.currentIndex + root.rows);
                        else if (event.key === Qt.Key_PageUp)
                            list.currentIndex = Math.max(0, list.currentIndex - root.rows);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.launch(root.results[list.currentIndex]);
                        else
                            return;
                        event.accepted = true;
                    }
                }

                Label {
                    readonly property int count: root.results.filter(r => r.run === undefined).length

                    text: `${count} ${count === 1 ? "app" : "apps"}`
                    font.pixelSize: 11
                    color: Theme.overlay0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.surface0
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.preferredHeight: root.rows * root.rowHeight + 16
                Layout.margins: 0
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
                    readonly property bool isCommand: modelData.run !== undefined
                    readonly property string icon: isCommand ? "" : Quickshell.iconPath(modelData.icon, true)
                    readonly property bool current: ListView.isCurrentItem

                    width: list.width
                    height: root.rowHeight

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 14

                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32

                            IconImage {
                                anchors.fill: parent
                                visible: !!row.icon
                                source: row.icon
                                asynchronous: true
                            }
                            // Command row, or an app without a themed icon
                            Rectangle {
                                anchors.fill: parent
                                visible: !row.icon
                                radius: 8
                                color: Theme.alpha(row.isCommand ? Theme.green : Theme.lavender, 0.15)

                                Label {
                                    anchors.centerIn: parent
                                    text: row.isCommand ? Theme.glyph(0xf018d) : row.modelData.name[0].toUpperCase() // 󰆍
                                    font.pixelSize: row.isCommand ? 16 : 14
                                    font.bold: true
                                    color: row.isCommand ? Theme.green : Theme.lavender
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: row.isCommand ? `Run “${row.modelData.run}”` : row.modelData.name
                                font.pixelSize: 13
                                font.bold: row.current
                                color: row.current ? Theme.lavender : Theme.text
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: !!text
                                text: row.isCommand ? (row.modelData.run.startsWith("ssh ") ? "Open in terminal" : "Run as a command") : row.modelData.comment || row.modelData.genericName
                                font.pixelSize: 11
                                color: Theme.overlay1
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = row.index
                        onClicked: root.launch(row.modelData)
                    }
                }
            }

            // Key hints
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.surface0
            }
            Label {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                horizontalAlignment: Text.AlignHCenter
                text: "↑↓  select     ⏎  launch     esc  close"
                font.pixelSize: 10
                color: Theme.overlay0
            }
        }
    }
}
