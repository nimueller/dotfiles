import QtQuick

// One workspace in the overview (overview.qml): a frame in the monitor's
// shape with its windows' pictures (OverviewWindow.qml), its name
// underneath. Takes windows dragged onto it.
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
    height: view.tileHeight + 24

    Rectangle {
        id: frame

        width: tile.view.tileWidth
        height: tile.view.tileHeight
        radius: 10
        clip: true
        color: drop.containsDrag ? Theme.surface1 : mouse.containsMouse ? Theme.surface0 : Theme.mantle
        border.width: tile.active || drop.containsDrag ? 2 : 1
        border.color: drop.containsDrag ? Theme.mauve : tile.active ? Theme.lavender : Theme.surface1

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

    Label {
        anchors.horizontalCenter: frame.horizontalCenter
        anchors.top: frame.bottom
        anchors.topMargin: 6
        text: tile.title
        font.bold: tile.active
        color: tile.active ? Theme.lavender : Theme.subtext0
    }
}
