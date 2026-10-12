import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Card above the right end of the bar (its centre for the clock, its left end
// for the system menu), shared
// by the bar menus. Closes on Escape or a click outside; `toggle.sh <name>`
// opens and closes it. Menus are short-lived instances that quit on close,
// unless `resident` (inside daemon.qml): then they only hide, and toggle()
// shows them again.
PanelWindow {
    id: root

    required property string name
    property int cardWidth: 380
    property bool centered: false
    property bool atLeft: false
    property bool resident: false
    property bool shown: !resident
    property real closedAt: 0
    default property alias content: body.data

    function close() {
        if (resident) {
            shown = false;
            closedAt = Date.now();
            return;
        }
        // Clicking the bar icon clears the grab before the bar runs toggle.sh;
        // the stamp tells toggle.sh not to reopen the menu right away.
        Quickshell.execDetached(["touch", `${Quickshell.env("XDG_RUNTIME_DIR")}/qs-${name}-closed`]);
        // Let go of the keyboard focus and the window before quitting: tearing
        // down a still focused item crashed in Qt's input method now and then
        // (QInputMethod::commit while the items were deleted)
        card.focus = false;
        shown = false;
        Qt.callLater(Qt.quit);
    }

    // Resident menus: a click on the bar icon first closes the menu through
    // the focus grab, so ignore the toggle that follows right after
    function toggle() {
        if (shown)
            close();
        else if (Date.now() - closedAt > 400)
            shown = true;
    }

    onShownChanged: {
        if (shown) {
            card.opacity = 0;
            slide.y = 12;
            intro.restart();
        }
    }

    visible: shown

    anchors {
        bottom: true
        right: !centered && !atLeft
        left: atLeft
    }
    margins {
        bottom: 6
        right: centered || atLeft ? 0 : 6
        left: atLeft ? 6 : 0
    }

    implicitWidth: cardWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: `quickshell-${name}`
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    HyprlandFocusGrab {
        active: root.shown
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
