import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Card above the right end of the bar (or its centre, for the clock), shared
// by the bar menus. Closes on Escape or a click outside; `toggle.sh <name>`
// opens and closes it.
PanelWindow {
    id: root

    required property string name
    property int cardWidth: 380
    property bool centered: false
    default property alias content: body.data

    function close() {
        // Clicking the bar icon clears the grab before waybar runs toggle.sh;
        // the stamp tells toggle.sh not to reopen the menu right away.
        Quickshell.execDetached(["touch", `${Quickshell.env("XDG_RUNTIME_DIR")}/qs-${name}-closed`]);
        Qt.quit();
    }

    anchors {
        bottom: true
        right: !centered
    }
    margins {
        bottom: 6
        right: centered ? 0 : 6
    }

    implicitWidth: cardWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: `quickshell-${name}`
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    HyprlandFocusGrab {
        active: true
        windows: [root]
        onCleared: root.close()
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: body.implicitHeight + 32
        radius: 12
        color: Theme.base
        border.width: 1
        border.color: Theme.surface0

        focus: true
        Keys.onEscapePressed: root.close()

        // Slide up out of the bar
        opacity: 0
        transform: Translate { id: slide; y: 12 }
        Component.onCompleted: intro.start()
        ParallelAnimation {
            id: intro
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: slide; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: body

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            spacing: 16
        }
    }
}
