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
//
// It opens by zooming out of the screen: the tiles are drawn like the real
// workspaces, wallpaper included, and start out so big that the active one
// covers the screen exactly. Going to a workspace zooms into its tile. The
// bar stays: the window leaves it out, so a tile is what a workspace shows.
ShellRoot {
    id: root

    // The tile being zoomed into on the way out, null to go back to the active
    // workspace
    property var target: null
    property bool leaving: false
    readonly property int duration: 280

    // What the overview does on the way out happens behind it: Hyprland's own
    // workspace animation would only show as a second one afterwards
    function leave(tile, command) {
        if (leaving)
            return;
        target = tile ?? null;
        leaving = true;
        if (command) {
            dispatch("function() hl.config({ animations = { enabled = false } }) end");
            dispatch(command);
            restoreAnimation.running = true;
        }
        closing.restart();
    }

    function close() {
        leave(null, "");
    }

    function dispatch(command) {
        Hyprland.dispatch(command);
    }

    // Go somewhere and close; the window's workspace comes along
    function focusWindow(toplevel, tile) {
        leave(tile, `hl.dsp.focus({ window = "address:0x${toplevel.address}" })`);
    }

    function focusWorkspace(id, tile) {
        leave(tile, `hl.dsp.focus({ workspace = ${JSON.stringify(id)} })`);
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
    Timer {
        id: closing
        interval: root.duration + 20
        onTriggered: Menus.close("overview")
    }
    Timer {
        id: restoreAnimation
        interval: 100
        onTriggered: root.dispatch("function() hl.config({ animations = { enabled = true } }) end")
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
            readonly property var toplevels: Hyprland.toplevels.values.filter(t => workspaces.includes(t.workspace))

            // Tiles in the shape of the screen without the bar, as big as fit
            // in one row up to a third of the screen, in rows of five otherwise
            readonly property real aspect: width / Math.max(1, height)
            readonly property int count: workspaces.length + 1
            readonly property int columns: Math.min(count, 5)
            readonly property real tileWidth: Math.min(width * 0.33, (width - 80 - (columns - 1) * 24) / columns)
            readonly property real tileHeight: tileWidth / aspect
            // Logical pixels of the monitor to those of a tile
            readonly property real factor: tileWidth / Math.max(1, width)
            // Where the window starts on the monitor, past the bar if it's
            // left or on top
            readonly property var reserved: monitor?.lastIpcObject?.reserved ?? [0, 0, 0, 0]
            readonly property real originX: (monitor?.x ?? 0) + reserved[0]
            readonly property real originY: (monitor?.y ?? 0) + reserved[1]

            // 0: a tile covers the screen, 1: the overview
            property real progress: 0
            readonly property bool settled: progress === 1 && !root.leaving

            readonly property var activeTile: tiles.children.find(t => t.active) ?? null
            readonly property var zoomTile: root.leaving && tiles.children.includes(root.target) ? root.target : activeTile
            readonly property real zoom: zoomTile ? width / tileWidth : 1

            // The zoom starts with a capture of the screen in the active tile:
            // that's the first frame and takes one capture's time. A capture
            // takes as long again per window (~150 ms) and they queue up, so
            // the windows come after it, one by one, the active workspace's
            // last as the screen already shows them. See OverviewWindow.qml.
            property bool ready: false
            property int pictures: 0
            readonly property var captures: toplevels.slice().sort((a, b) => (a.workspace === monitor?.activeWorkspace) - (b.workspace === monitor?.activeWorkspace))

            function tileFor(id) {
                return tiles.children.find(t => t.workspace?.id === id) ?? newTile;
            }

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Normal
            color: "transparent"

            WlrLayershell.namespace: "quickshell-overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Timer {
                running: true
                interval: 300
                onTriggered: win.ready = true
            }
            // A window that's never captured mustn't hold up the others
            Timer {
                running: win.settled && win.pictures < win.captures.length
                repeat: true
                interval: 500
                onTriggered: win.pictures++
            }

            NumberAnimation on progress {
                running: win.ready && !root.leaving
                to: 1
                duration: root.duration
                easing.type: Easing.OutCubic
            }
            NumberAnimation on progress {
                running: root.leaving
                to: 0
                duration: root.duration
                easing.type: Easing.InOutCubic
            }

            Item {
                anchors.fill: parent
                // Not hidden: only what's visible gets captured
                opacity: win.ready ? 1 : 0.004

                // The wallpaper from a few pixels: blurred, and cheap to draw
                Image {
                    anchors.fill: parent
                    source: `file://${Quickshell.env("HOME")}/.config/hypr/wallpapers/MountainDark.jpg`
                    sourceSize.width: 48
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                }
                Rectangle {
                    anchors.fill: parent
                    color: Theme.alpha(Theme.crust, 0.6)
                }

                // Next to the workspaces: close
                MouseArea {
                    anchors.fill: parent
                    enabled: win.settled
                    onClicked: root.close()
                }

                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: event => {
                        const n = event.text === "0" ? 10 : parseInt(event.text);
                        if (event.key === Qt.Key_Escape)
                            root.close();
                        else if (n >= 1 && n <= 10)
                            root.focusWorkspace(n, win.tileFor(n));
                    }
                }

                // The camera: moved so that the tile being zoomed into stays
                // on the screen's corner while it grows
                Item {
                    id: stage

                    anchors.fill: parent
                    enabled: win.settled

                    transform: [
                        Scale {
                            xScale: 1 + (win.zoom - 1) * (1 - win.progress)
                            yScale: xScale
                        },
                        Translate {
                            x: -(win.zoomTile ? tiles.x + win.zoomTile.x : 0) * win.zoom * (1 - win.progress)
                            y: -(win.zoomTile ? tiles.y + win.zoomTile.y : 0) * win.zoom * (1 - win.progress)
                        }
                    ]

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
                                onActivated: root.focusWorkspace(modelData.id, this)
                                onDropped: toplevel => root.moveWindow(toplevel, modelData.id, win.monitor)
                                onWindowClicked: toplevel => root.focusWindow(toplevel, this)
                            }
                        }

                        // A new, empty workspace on this monitor
                        OverviewTile {
                            id: newTile

                            view: win
                            title: "New"
                            toplevels: []
                            onActivated: {
                                root.dispatch(`hl.dsp.focus({ monitor = "${win.monitor.name}" })`);
                                root.focusWorkspace("emptym", this);
                            }
                            onDropped: toplevel => root.moveWindow(toplevel, "emptym", win.monitor)

                            Label {
                                anchors.centerIn: parent
                                text: "+"
                                font.pixelSize: 32
                                color: Theme.text
                                opacity: win.progress
                            }
                        }
                    }
                }
            }
        }
    }
}
