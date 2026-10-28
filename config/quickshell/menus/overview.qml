// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Overview of the workspaces: on every monitor its workspaces side by side,
// each with pictures of its windows where they are. Click (or tap) a window
// to go to it, a workspace to switch to it, the + for a new one; drag a
// window onto another workspace (or the +) to move it there. Escape, a click
// next to the workspaces or the same key again close it.
//
// Opened with SUPER + W (keybinds.lua), a three-finger swipe up on a touchpad
// or a touch screen with hyprgrass (modes.lua), a click on the active
// workspace in the bar (Workspaces.qml) or `toggle.sh overview`. A menu of
// the daemon (Menus.qml), so the pictures only exist while it's open; they
// are taken once as it opens (ScreencopyView, not live), windows on hidden
// workspaces included.
ShellRoot {
    id: root

    function close() {
        Menus.close("overview");
    }

    function dispatch(command) {
        Hyprland.dispatch(command);
    }

    // Go somewhere and close; the window's workspace comes along
    function focusWindow(toplevel) {
        dispatch(`hl.dsp.focus({ window = "address:0x${toplevel.address}" })`);
        close();
    }

    function focusWorkspace(id) {
        dispatch(`hl.dsp.focus({ workspace = ${JSON.stringify(id)} })`);
        close();
    }

    // `workspace`: an id, or "emptym" for a new one on that monitor
    function moveWindow(toplevel, workspace, monitor) {
        if (workspace === "emptym")
            dispatch(`hl.dsp.focus({ monitor = "${monitor.name}" })`);
        dispatch(`hl.dsp.window.move({ workspace = ${JSON.stringify(workspace)}, window = "address:0x${toplevel.address}" })`);
        refresh.restart();
    }

    // The windows' positions are only in the IPC data
    Component.onCompleted: {
        Hyprland.refreshToplevels();
        Hyprland.refreshMonitors();
    }
    Timer {
        id: refresh
        interval: 150
        onTriggered: Hyprland.refreshToplevels()
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win

            required property var modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool focused: Hyprland.focusedMonitor === monitor

            // Its workspaces in order, the + after them
            readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.monitor === monitor && w.id > 0).sort((a, b) => a.id - b.id)

            // Tiles in the monitor's shape, as big as fit in one row up to a
            // quarter of the screen, in rows of five otherwise
            readonly property real aspect: (monitor?.width ?? 16) / Math.max(1, monitor?.height ?? 9)
            readonly property int count: workspaces.length + 1
            readonly property int columns: Math.min(count, 5)
            readonly property real tileWidth: Math.min(width * 0.25, (width - 80 - (columns - 1) * 24) / columns)
            readonly property real tileHeight: tileWidth / aspect
            // Logical pixels of the monitor to those of a tile
            readonly property real factor: tileWidth * (monitor?.scale ?? 1) / Math.max(1, monitor?.width ?? 1)

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.alpha(Theme.crust, 0.92)

            WlrLayershell.namespace: "quickshell-overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Next to the workspaces: close
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    const n = parseInt(event.text);
                    if (event.key === Qt.Key_Escape)
                        root.close();
                    else if (n >= 1 && n <= 9)
                        root.focusWorkspace(n);
                    else if (event.text === "0")
                        root.focusWorkspace(10);
                }
            }

            Flow {
                id: tiles

                anchors.centerIn: parent
                width: Math.min(win.columns, win.count) * (win.tileWidth + spacing) - spacing
                spacing: 24

                Repeater {
                    model: win.workspaces

                    delegate: OverviewTile {
                        required property var modelData

                        view: win

                        workspace: modelData
                        title: modelData.name
                        active: win.monitor?.activeWorkspace === modelData
                        toplevels: Hyprland.toplevels.values.filter(t => t.workspace === modelData)
                        onActivated: root.focusWorkspace(modelData.id)
                        onDropped: toplevel => root.moveWindow(toplevel, modelData.id, win.monitor)
                        onWindowClicked: toplevel => root.focusWindow(toplevel)
                    }
                }

                // A new, empty workspace on this monitor
                OverviewTile {
                    view: win
                    title: "New"
                    toplevels: []
                    onActivated: {
                        root.dispatch(`hl.dsp.focus({ monitor = "${win.monitor.name}" })`);
                        root.focusWorkspace("emptym");
                    }
                    onDropped: toplevel => root.moveWindow(toplevel, "emptym", win.monitor)

                    Label {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -12
                        text: "+"
                        font.pixelSize: 32
                        color: Theme.overlay1
                    }
                }
            }
        }
    }
}
