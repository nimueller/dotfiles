import QtQuick
import Quickshell
import Quickshell.Wayland

// One workspace in the overview (overview.qml): a miniature of it, the
// wallpaper with the windows' pictures (OverviewWindow.qml) where they are.
// Takes windows dragged onto it.
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

    width: view.tileWidth
    height: view.tileHeight

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
}
