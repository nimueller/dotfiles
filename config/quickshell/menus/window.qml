// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Details of the focused window (SUPER+I, keybinds.lua): title, class, PID
// and command, workspace, monitor, geometry and state, as Hyprland reports
// them, and whether the app runs as a Flatpak. Click a row to copy its
// value; I18n.tr("Copy all") copies Hyprland's JSON.
Popup {
    id: root

    name: "window"
    centered: true
    cardWidth: 520

    property var win: null // hyprctl activewindow -j; null while loading, {} without a focused window
    property string json: ""
    property string command: ""
    property var flatpak: null // .flatpak-info as {key: value}; {} for no Flatpak, null while loading
    property string copied: ""

    readonly property var entry: win?.class ? DesktopEntries.heuristicLookup(win.class) : null

    function copy(label, value) {
        Quickshell.execDetached(["wl-copy", "--", value]);
        copied = label;
        copiedTimer.restart();
    }

    function layoutState(w) {
        if (w.fullscreen === 2) {
            return I18n.tr("Fullscreen");
        }
        if (w.fullscreen === 1) {
            return I18n.tr("Maximized");
        }
        if (w.floating) {
            return I18n.tr("Floating");
        }
        return I18n.tr("Tiled");
    }

    function state(w) {
        const s = [layoutState(w)];
        if (w.pinned) {
            s.push(I18n.tr("pinned"));
        }
        if (w.grouped?.length) {
            s.push(I18n.tr("grouped (%1)", w.grouped.length));
        }
        if (w.inhibitingIdle) {
            s.push(I18n.tr("keeps the screen awake"));
        }
        return s.join(", ");
    }

    function flatpakText(info) {
        if (!info) {
            return "";
        }
        if (!info.name) {
            return I18n.tr("No");
        }
        const appPath = info["app-path"];
        let installation = "";
        if (appPath) {
            installation = appPath.startsWith("/var/lib/") ? I18n.tr("system") : I18n.tr("user");
        }
        const details = [info.branch, installation].filter(d => d);
        return details.length ? `${info.name} (${details.join(", ")})` : info.name;
    }

    // [label, value] for every detail the window has
    readonly property var rows: {
        if (!win?.address) {
            return [];
        }
        const monitor = Hyprland.monitors.values.find(m => m.id === win.monitor)?.name ?? String(win.monitor);
        const list = [];
        list.push([I18n.tr("Title"), win.title]);
        list.push([I18n.tr("Class"), win.class]);
        list.push([I18n.tr("Initial class"), win.initialClass !== win.class ? win.initialClass : ""]);
        list.push([I18n.tr("Initial title"), win.initialTitle !== win.title ? win.initialTitle : ""]);
        list.push([I18n.tr("App"), entry ? `${entry.name} (${entry.id}.desktop)` : ""]);
        list.push(["PID", String(win.pid)]);
        list.push([I18n.tr("Command"), command]);
        list.push(["Flatpak", flatpakText(flatpak)]);
        list.push([I18n.tr("Workspace"), win.workspace.name]);
        list.push([I18n.tr("Monitor"), monitor]);
        list.push([I18n.tr("Position"), `${win.at[0]}, ${win.at[1]}`]);
        list.push([I18n.tr("Size"), `${win.size[0]} × ${win.size[1]}`]);
        list.push([I18n.tr("State"), state(win)]);
        list.push([I18n.tr("Protocol"), win.xwayland ? "XWayland" : "Wayland"]);
        list.push([I18n.tr("Content"), win.contentType !== "none" ? win.contentType : ""]);
        list.push([I18n.tr("Tags"), win.tags.join(", ")]);
        list.push([I18n.tr("Address"), win.address]);
        return list.filter(r => r[1]);
    }

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
                if (root.win?.pid > 0) {
                    cmdline.running = true;
                    flatpakInfo.running = true;
                }
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

    // Flatpak puts .flatpak-info at the root of its sandbox. Processes that
    // aren't dumpable hide their root, so fall back to the systemd scope
    // `flatpak run` starts them in (app-flatpak-<app id>-<instance>.scope).
    Process {
        id: flatpakInfo
        command: ["sh", "-c", 'cat "/proc/$1/root/.flatpak-info" 2>/dev/null || sed -n "s/.*app-flatpak-\\(.*\\)-[0-9]*\\.scope$/name=\\1/p" "/proc/$1/cgroup"', "sh", String(root.win?.pid ?? 0)]
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {};
                for (const line of text.split("\n")) {
                    // [Application] and [Instance] come first and hold the keys shown here
                    if (line.startsWith("[Context]")) {
                        break;
                    }
                    const i = line.indexOf("=");
                    if (i > 0) {
                        info[line.slice(0, i)] = line.slice(i + 1);
                    }
                }
                root.flatpak = info;
            }
        }
    }

    Header {
        glyph: Theme.glyph(0xf05b6) // 󰖶
        accent: Theme.sapphire
        // Long titles shortened to leave room for the button; the Title row has all of it
        title: {
            if (root.win === null) {
                return I18n.tr("Window");
            }
            if (!root.win.address) {
                return I18n.tr("No focused window");
            }
            const t = root.win.title || root.win.class;
            return t.length > 48 ? `${t.slice(0, 47)}…` : t;
        }

        IconButton {
            visible: !!root.win?.address
            glyph: Theme.glyph(root.copied === "all" ? 0xf012c : 0xf018f) // 󰄬 / 󰆏
            text: root.copied === "all" ? I18n.tr("Copied") : I18n.tr("Copy all")
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
                color: {
                    if (isCopied) {
                        return Theme.alpha(Theme.green, 0.15);
                    }
                    if (mouse.containsMouse) {
                        return Theme.surface0;
                    }
                    return "transparent";
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

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
                    text: row.isCopied ? `${Theme.glyph(0xf012c)} ${I18n.tr("Copied")}` : Theme.glyph(0xf018f) // 󰄬 / 󰆏
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
        text: I18n.tr("The focused workspace has no window.")
        color: Theme.subtext0
    }
}
