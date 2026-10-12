// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Details of the focused window (SUPER+I, keybinds.lua): title, class, PID
// and command, workspace, monitor, geometry and state, as Hyprland reports
// them. Click a row to copy its value; "Copy all" copies Hyprland's JSON.
Popup {
    id: root

    name: "window"
    centered: true
    cardWidth: 520

    property var win: null // hyprctl activewindow -j; null while loading, {} without a focused window
    property string json: ""
    property string command: ""
    property string copied: ""

    readonly property var entry: win?.class ? DesktopEntries.heuristicLookup(win.class) : null

    function copy(label, value) {
        Quickshell.execDetached(["wl-copy", "--", value]);
        copied = label;
        copiedTimer.restart();
    }

    function state(w) {
        const s = [w.fullscreen === 2 ? "Fullscreen" : w.fullscreen === 1 ? "Maximized" : w.floating ? "Floating" : "Tiled"];
        if (w.pinned)
            s.push("pinned");
        if (w.grouped?.length)
            s.push(`grouped (${w.grouped.length})`);
        if (w.inhibitingIdle)
            s.push("keeps the screen awake");
        return s.join(", ");
    }

    readonly property var rows: !win?.address ? [] : [
        ["Title", win.title],
        ["Class", win.class],
        ["Initial class", win.initialClass !== win.class ? win.initialClass : ""],
        ["Initial title", win.initialTitle !== win.title ? win.initialTitle : ""],
        ["App", entry ? `${entry.name} (${entry.id}.desktop)` : ""],
        ["PID", String(win.pid)],
        ["Command", command],
        ["Workspace", win.workspace.name],
        ["Monitor", Hyprland.monitors.values.find(m => m.id === win.monitor)?.name ?? String(win.monitor)],
        ["Position", `${win.at[0]}, ${win.at[1]}`],
        ["Size", `${win.size[0]} × ${win.size[1]}`],
        ["State", state(win)],
        ["Protocol", win.xwayland ? "XWayland" : "Wayland"],
        ["Content", win.contentType !== "none" ? win.contentType : ""],
        ["Tags", win.tags.join(", ")],
        ["Address", win.address]
    ].filter(r => r[1])

    Timer {
        id: copiedTimer
        interval: 1500
        onTriggered: root.copied = ""
    }

    Process {
        running: true
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.json = text.trim();
                try {
                    root.win = JSON.parse(root.json);
                } catch (e) {
                    root.win = {};
                }
                if (root.win?.pid > 0)
                    cmdline.running = true;
            }
        }
    }

    // The process's full command line (arguments separated by NULs)
    Process {
        id: cmdline
        command: ["sh", "-c", 'tr "\\0" " " < "/proc/$1/cmdline"', "sh", String(root.win?.pid ?? 0)]
        stdout: StdioCollector {
            onStreamFinished: root.command = text.trim()
        }
    }

    Header {
        glyph: Theme.glyph(0xf05b6) // 󰖶
        accent: Theme.sapphire
        title: root.win === null ? "Window" : root.win.address ? (root.entry?.name ?? root.win.class) : "No focused window"

        IconButton {
            visible: !!root.win?.address
            glyph: Theme.glyph(root.copied === "all" ? 0xf012c : 0xf018f) // 󰄬 / 󰆏
            text: root.copied === "all" ? "Copied" : "Copy all"
            active: root.copied === "all"
            onClicked: root.copy("all", root.json)
        }
    }

    // Details: click a row to copy its value
    Column {
        visible: root.rows.length > 0
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: root.rows

            delegate: Rectangle {
                id: row

                required property var modelData
                readonly property bool isCopied: root.copied === modelData[0]

                width: parent.width
                implicitHeight: Math.max(26, value.implicitHeight + 8)
                radius: 6
                color: isCopied ? Theme.alpha(Theme.green, 0.15) : mouse.containsMouse ? Theme.surface0 : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }

                Label {
                    x: 8
                    width: 100
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData[0]
                    color: Theme.overlay1
                }
                Label {
                    id: value

                    x: 108
                    width: parent.width - 108 - 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData[1]
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                }
                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isCopied || mouse.containsMouse
                    text: row.isCopied ? `${Theme.glyph(0xf012c)} Copied` : Theme.glyph(0xf018f) // 󰄬 / 󰆏
                    color: row.isCopied ? Theme.green : Theme.overlay1
                    font.pixelSize: 11
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copy(row.modelData[0], row.modelData[1])
                }
            }
        }
    }

    Label {
        visible: root.win !== null && !root.win.address
        Layout.fillWidth: true
        text: "The focused workspace has no window."
        color: Theme.subtext0
    }
}
