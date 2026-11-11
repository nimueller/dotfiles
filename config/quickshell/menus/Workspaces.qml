import QtQuick
import Quickshell
import Quickshell.Hyprland

// The workspaces of one monitor in a chip: the active one as a lavender
// pill, a special workspace only while it's shown on this monitor (mauve),
// urgent ones in peach. Click to switch, the active one for the overview of
// all workspaces (overview.qml), scroll to move along like SUPER + wheel.
Rectangle {
    id: root

    required property var monitor // HyprlandMonitor
    readonly property string special: monitor?.lastIpcObject?.specialWorkspace?.name ?? ""
    readonly property var workspaces: {
        const isShown = w => w.monitor === monitor && (w.id > 0 || w.name === special);
        const specialLast = (a, b) => (a.id < 0) - (b.id < 0) || a.id - b.id;
        return Hyprland.workspaces.values.filter(isShown).sort(specialLast);
    }

    implicitWidth: row.implicitWidth + 6
    implicitHeight: Modes.barSize(19, 30, 36)
    radius: 8
    color: Theme.surface0

    // The special workspace shown on a monitor is only in its IPC data
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name.startsWith("activespecial")) {
                Hyprland.refreshMonitors();
            }
        }
    }
    Component.onCompleted: Hyprland.refreshMonitors()

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.workspaces

            delegate: Rectangle {
                id: button

                required property var modelData
                readonly property bool isSpecial: modelData.id < 0
                readonly property bool active: isSpecial || root.monitor?.activeWorkspace === modelData

                implicitWidth: Math.max(Modes.barSize(30, 44, 52), label.implicitWidth + 22)
                implicitHeight: Modes.barSize(15, 24, 30)
                radius: 6
                color: {
                    if (active) {
                        if (isSpecial) {
                            return Theme.mauve;
                        }
                        return Theme.lavender;
                    }
                    if (modelData.urgent) {
                        return Theme.peach;
                    }
                    if (mouse.containsMouse || mouse.pressed) {
                        return Theme.surface1;
                    }
                    return "transparent";
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                BarLabel {
                    id: label
                    anchors.centerIn: parent
                    text: button.isSpecial ? button.modelData.name.replace("special:", "") : button.modelData.name
                    font.bold: button.active
                    color: {
                        if (button.active || button.modelData.urgent) {
                            return Theme.crust;
                        }
                        if (mouse.containsMouse) {
                            return Theme.text;
                        }
                        return Theme.overlay2;
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    // Touch: up to the bar's edges
                    anchors.topMargin: Modes.touch ? -8 : 0
                    anchors.bottomMargin: Modes.touch ? -8 : 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Lua dispatchers: Quickshell 0.3.1 doesn't detect the Lua
                    // config, so HyprlandWorkspace.activate() does nothing
                    onClicked: {
                        if (button.active && !button.isSpecial) {
                            Hyprland.dispatch(`hl.dsp.event("quickshell-overview")`);
                        } else if (button.isSpecial) {
                            Hyprland.dispatch(`hl.dsp.workspace.toggle_special("${label.text}")`);
                        } else {
                            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${button.modelData.id} })`);
                        }
                    }
                }
            }
        }
    }

    // On top of the buttons but takes no buttons, so clicks and hover still
    // reach them: a WheelHandler got no wheel events from a real mouse in the
    // Quickshell window
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: event => Hyprland.dispatch(`hl.dsp.focus({ workspace = "e${event.angleDelta.y > 0 ? "-" : "+"}1" })`)
    }
}
