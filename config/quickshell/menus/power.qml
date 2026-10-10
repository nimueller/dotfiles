import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Full-screen power menu: a centred row of round buttons, one accent each.
// Arrow keys / Tab to move, Enter or the letter to pick, Escape or a click on
// the backdrop to close.
PanelWindow {
    id: root

    readonly property var actions: [
        { text: "Lock", key: "L", glyph: 0xf033e, accent: Theme.lavender, command: "hyprlock" },
        { text: "Log out", key: "E", glyph: 0xf0343, accent: Theme.blue, command: "hyprctl dispatch 'hl.dsp.exit()'" },
        { text: "Suspend", key: "U", glyph: 0xf0904, accent: Theme.mauve, command: "systemctl suspend" },
        { text: "Reboot", key: "R", glyph: 0xf0709, accent: Theme.peach, command: "systemctl reboot" },
        { text: "Shut down", key: "S", glyph: 0xf0425, accent: Theme.red, command: "systemctl poweroff" }
    ]
    property int selected: 0
    property string uptime: ""

    function run(action) {
        Quickshell.execDetached(["sh", "-c", action.command]);
        Qt.quit();
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "quickshell-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Process {
        running: true
        command: ["cut", "-d.", "-f1", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = parseInt(text);
                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                root.uptime = `up ${d ? `${d}d ` : ""}${h ? `${h}h ` : ""}${m}m`;
            }
        }
    }

    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: Theme.alpha(Theme.crust, 0.8)
        opacity: 0
        Component.onCompleted: opacity = 1

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
        }

        Column {
            anchors.centerIn: parent
            spacing: 40

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 32

                Repeater {
                    model: root.actions

                    delegate: PowerButton {
                        required property var modelData
                        required property int index

                        action: modelData
                        selected: root.selected === index
                        onHoverEntered: root.selected = index
                        onTriggered: root.run(modelData)
                    }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: `${Theme.glyph(0xf0954)}  ${root.uptime}` // 󰥔
                visible: !!root.uptime
                color: Theme.overlay1
            }
        }

        focus: true
        Keys.onPressed: event => {
            const n = root.actions.length;
            if (event.key === Qt.Key_Escape)
                Qt.quit();
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || event.key === Qt.Key_H)
                root.selected = (root.selected + n - 1) % n;
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_J)
                root.selected = (root.selected + 1) % n;
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                root.run(root.actions[root.selected]);
            else {
                const action = root.actions.find(a => a.key === event.text.toUpperCase());
                if (action)
                    root.run(action);
            }
        }
    }
}
