import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Overview of the workspaces: on every monitor its workspaces side by side,
// each with pictures of its windows where they are. Click (or tap) a window
// to go to it, a workspace to switch to it, the + for a new one; drag a
// window onto another workspace (or the +) to move it there. The x on a
// window closes it, "Close workspace" under a workspace all of its windows,
// after a second press: the workspace goes when its last window does. Escape, a click
// next to the workspaces or the same key again close it.
//
// Opened with SUPER + W (keybinds.lua), a three-finger swipe up on a touchpad
// or a touch screen with hyprgrass (modes.lua), a click on the active
// workspace in the bar (Workspaces.qml) or `toggle.sh overview`: all of them
// send hl.dsp.event("quickshell-overview"), which toggles it; the swipes add
// "open", and "close" for the same swipe down. The pictures only exist while
// it's open; they are taken once as it opens (ScreencopyView, not live),
// windows on hidden workspaces included.
//
// A resident process of its own, started with Hyprland (autostart.lua), not a
// menu of daemon.qml, because it needs the GPU: the daemon renders in software,
// where the zoom ran at half the frames and a capture took ~150 ms per window
// (SHM buffers, one after the other), against ~170 ms for all of them with
// dmabufs. Without the window it holds no GPU memory. Apply changes with
// `toggle.sh overview --restart`.
//
// It opens by zooming out of the screen: the tiles are drawn like the real
// workspaces, wallpaper included, and start out so big that the active one
// covers the screen exactly. Going to a workspace zooms into its tile. The
// bar stays: the window leaves it out, so a tile is what a workspace shows.
ShellRoot {
    id: root

    // No live reload, like the daemon
    settings.watchFiles: false

    property bool open: false

    // The tile being zoomed into on the way out, null to go back to the active
    // workspace
    property var target: null
    property bool leaving: false
    readonly property int duration: 280

    function show() {
        if (open)
            return;
        target = null;
        leaving = false;
        // The windows' positions are only in the IPC data
        Hyprland.refreshToplevels();
        Hyprland.refreshMonitors();
        open = true;
    }

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

    function closeWindows(toplevels) {
        for (const toplevel of toplevels)
            dispatch(`hl.dsp.window.close({ window = "address:0x${toplevel.address}" })`);
        refresh.restart();
    }

    // `workspace`: an id, or "emptym" for a new one on that monitor
    function moveWindow(toplevel, workspace, monitor) {
        if (workspace === "emptym")
            dispatch(`hl.dsp.focus({ monitor = "${monitor.name}" })`);
        dispatch(`hl.dsp.window.move({ workspace = ${JSON.stringify(workspace)}, window = "address:0x${toplevel.address}" })`);
        refresh.restart();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "custom")
                return;
            if (event.data === "quickshell-overview")
                root.open ? root.close() : root.show();
            else if (event.data === "quickshell-overview open")
                root.show();
            else if (event.data === "quickshell-overview close" && root.open)
                root.close();
        }
    }

    // Quickshell sets up its buffers with the first ScreencopyView, waiting
    // for a window's scene graph to start. That has to be a window yet to
    // come; for one in a window of a process that's been up, it never ends.
    ScreencopyView {}

    Timer {
        id: refresh
        interval: 150
        onTriggered: Hyprland.refreshToplevels()
    }
    Timer {
        id: closing
        interval: root.duration + 20
        onTriggered: root.open = false
    }
    Timer {
        id: restoreAnimation
        interval: 100
        onTriggered: root.dispatch("function() hl.config({ animations = { enabled = true } }) end")
    }

    LazyLoader {
        active: root.open

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
                onSettledChanged: if (settled)
                    arrived = true
                // From here on the tiles show what's there, not how it was
                property bool arrived: false

                readonly property var activeTile: tiles.children.find(t => t.active) ?? null
                readonly property var zoomTile: root.leaving && tiles.children.includes(root.target) ? root.target : activeTile
                readonly property real zoom: zoomTile ? width / tileWidth : 1

                // The first frame has to look like the screen, so the zoom waits
                // for its capture, but not for long
                property bool ready: false

                // Hyprland keeps an active workspace that's empty: go to the
                // one before it, so that it goes when its last window closes
                function leaveWorkspace(workspace) {
                    const others = workspaces.filter(w => w !== workspace);
                    const next = others.filter(w => w.id < workspace.id).pop() ?? others[0];
                    if (next)
                        root.dispatch(`hl.dsp.focus({ workspace = ${next.id} })`);
                }

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
                    interval: 500
                    onTriggered: win.ready = true
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
                        sourceSize: Qt.size(48, 32)
                        asynchronous: true
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
                                    onCloseWindows: toplevels => root.closeWindows(toplevels)
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
                                    anchors.verticalCenterOffset: -newTile.footer / 2
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
}
