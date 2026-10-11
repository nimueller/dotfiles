import QtQuick
import Quickshell
import Quickshell.Hyprland

// The workspaces of one monitor in a chip: the active one as a lavender
// pill, a special workspace only while it's shown on this monitor (mauve),
// urgent ones in peach. Click to switch, scroll to move along like SUPER +
// wheel.
Rectangle {
    id: root

    required property var monitor // HyprlandMonitor
    readonly property string special: monitor?.lastIpcObject?.specialWorkspace?.name ?? ""
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.monitor === monitor && (w.id > 0 || w.name === special)).sort((a, b) => (a.id < 0) - (b.id < 0) || a.id - b.id)

    implicitWidth: row.implicitWidth + 6
    implicitHeight: 19
    radius: 8
    color: Theme.surface0

    // The special workspace shown on a monitor is only in its IPC data
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name.startsWith("activespecial"))
                Hyprland.refreshMonitors();
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

                implicitWidth: Math.max(30, label.implicitWidth + 22)
                implicitHeight: 15
                radius: 6
                color: active ? (isSpecial ? Theme.mauve : Theme.lavender) : modelData.urgent ? Theme.peach : mouse.containsMouse ? Theme.surface1 : "transparent"

                Behavior on color { ColorAnimation { duration: 200 } }

                Label {
                    id: label
                    anchors.centerIn: parent
                    text: button.isSpecial ? button.modelData.name.replace("special:", "") : button.modelData.name
                    font.bold: button.active
                    color: button.active || button.modelData.urgent ? Theme.crust : mouse.containsMouse ? Theme.text : Theme.overlay2
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Lua dispatchers: Quickshell 0.3.1 doesn't detect the Lua
                    // config, so HyprlandWorkspace.activate() does nothing
                    onClicked: {
                        if (button.isSpecial)
                            Hyprland.dispatch(`hl.dsp.workspace.toggle_special("${label.text}")`);
                        else
                            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${button.modelData.id} })`);
                    }
                }
            }
        }
    }

    WheelHandler {
        onWheel: event => Hyprland.dispatch(`hl.dsp.focus({ workspace = "e${event.angleDelta.y > 0 ? "-" : "+"}1" })`)
    }
}
