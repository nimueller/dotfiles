import QtQuick
import Quickshell
import Quickshell.Wayland

// One workspace in the overview (overview.qml): a miniature of it, the
// wallpaper with the windows' pictures (OverviewWindow.qml) where they are.
// Takes windows dragged onto it. The x closes all of its windows, after a
// second press, as not all of them ask first.
Item {
    id: tile

    required property var view // the overview's PanelWindow
    property var workspace: null // HyprlandWorkspace, null for "New"
    property string title: ""
    property bool active: false
    required property var toplevels

    signal activated
    signal dropped(var toplevel)
    signal windowClicked(var toplevel)
    signal closeWindows(var toplevels)

    property bool closing: false // the first press on the x

    width: view.tileWidth
    height: view.tileHeight

    HoverHandler {
        id: hover
    }

    Item {
        id: frame

        anchors.fill: parent
        clip: true

        // As big as on the screen, so it lines up with the real one, and
        // like it starts behind the bar if that's on the left or on top
        Image {
            id: wallpaper
            x: -tile.view.reserved[0] * tile.view.factor
            y: -tile.view.reserved[1] * tile.view.factor
            width: tile.view.screen.width * tile.view.factor
            height: tile.view.screen.height * tile.view.factor
            source: `file://${Quickshell.env("HOME")}/.config/hypr/wallpapers/MountainDark.jpg`
            // The active tile starts as the screen, this one only ever is a tile
            sourceSize: Qt.size(960, 640)
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }

        // The screen, the first frame of the zoom
        ScreencopyView {
            x: wallpaper.x
            y: wallpaper.y
            width: wallpaper.width
            height: wallpaper.height
            captureSource: tile.active ? tile.view.modelData : null
            live: false
            onHasContentChanged: if (hasContent)
                tile.view.ready = true
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }

        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["overview-window"]
            // A window onto its own workspace stays
            onDropped: event => {
                const toplevel = event.source.toplevel;
                if (toplevel.workspace !== tile.workspace)
                    tile.dropped(toplevel);
            }
        }

        Repeater {
            model: tile.toplevels

            delegate: OverviewWindow {
                required property var modelData

                view: tile.view
                toplevel: modelData
                onClicked: tile.windowClicked(modelData)
                onCloseRequested: tile.closeWindows([modelData])
            }
        }
    }

    // Above the windows, and only once it isn't the whole screen any more
    Rectangle {
        anchors.fill: parent
        anchors.margins: -border.width
        color: "transparent"
        radius: 2
        border.width: 2
        border.color: drop.containsDrag ? Theme.mauve : tile.active ? Theme.lavender : mouse.containsMouse ? Theme.overlay1 : Theme.alpha(Theme.text, 0.15)
        opacity: tile.view.progress
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: Math.max(height, number.implicitWidth + 16)
        height: 24
        radius: 12
        color: tile.active ? Theme.lavender : Theme.alpha(Theme.crust, 0.8)
        opacity: tile.view.progress

        Label {
            id: number
            anchors.centerIn: parent
            text: tile.title
            font.bold: true
            color: tile.active ? Theme.crust : Theme.text
        }
    }

    // On the left: a window's own x is on its right
    IconButton {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 6
        z: 1
        visible: tile.toplevels.length > 0 && (tile.closing || hover.hovered || Modes.touch)
        opacity: tile.view.progress
        glyph: Theme.glyph(0xf0156) // 󰅖
        text: tile.closing ? `Close ${tile.toplevels.length === 1 ? "1 window" : `${tile.toplevels.length} windows`}` : ""
        accent: Theme.red
        active: tile.closing
        onClicked: {
            if (tile.closing) {
                tile.closing = false;
                tile.closeWindows(tile.toplevels);
            } else {
                tile.closing = true;
            }
        }

        Timer {
            running: tile.closing
            interval: 3000
            onTriggered: tile.closing = false
        }
    }
}
