import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

// One Bluetooth device: click to connect, disconnect or pair it
// (bluetooth.qml does it); the arrow opens a paired one for Forget.
Rectangle {
    id: root

    required property BluetoothDevice device
    property bool expanded: false
    property string error: ""

    signal activated
    signal toggleExpanded

    readonly property bool known: device.paired || device.bonded

    implicitHeight: column.implicitHeight + 12
    radius: 8
    color: {
        if (expanded) {
            return Theme.surface0;
        }
        if (mouse.containsMouse) {
            return Theme.alpha(Theme.surface0, 0.6);
        }
        return "transparent";
    }

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    // BlueZ's icon names, by what they're for
    function glyph(icon) {
        const glyphs = {
            // 󰋎
            "audio-headset": 0xf02ce,
            // 󰋋
            "audio-headphones": 0xf02cb,
            // 󰓃
            "audio-card": 0xf04c3,
            // 󰍽
            "input-mouse": 0xf037d,
            // 󰌌
            "input-keyboard": 0xf030c,
            // 󰊗
            "input-gaming": 0xf0297,
            // 󰓷
            "input-tablet": 0xf04f7,
            // 󰄜
            "phone": 0xf011c,
            // 󰌢
            "computer": 0xf0322,
            // 󰕧
            "camera-video": 0xf0567,
            "printer": 0xf042a // 󰐪
        };
        return Theme.glyph(glyphs[icon] ?? 0xf00af); // 󰂯
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    ColumnLayout {
        id: column

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 6
            leftMargin: 10
            rightMargin: 6
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Modes.touch ? 30 : 22
            spacing: 10

            Label {
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
                text: root.glyph(root.device.icon)
                color: root.device.connected ? Theme.blue : Theme.overlay2
            }
            Label {
                Layout.fillWidth: true
                text: root.device.name || root.device.address
                color: root.device.connected ? Theme.text : Theme.subtext1
                font.bold: root.device.connected
            }
            Label {
                readonly property int charge: Math.round(root.device.battery * 100)

                visible: root.device.connected && root.device.batteryAvailable
                text: `${Theme.batteryGlyph(charge)} ${charge}%`
                font.pixelSize: 10
                color: {
                    if (charge <= 15) {
                        return Theme.red;
                    }
                    if (charge <= 30) {
                        return Theme.yellow;
                    }
                    return Theme.green;
                }
            }
            Label {
                text: {
                    if (root.device.pairing) {
                        return "Pairing…";
                    }
                    if (root.device.state === BluetoothDeviceState.Connecting) {
                        return "Connecting…";
                    }
                    if (root.device.state === BluetoothDeviceState.Disconnecting) {
                        return "Disconnecting…";
                    }
                    if (root.device.connected) {
                        return "Connected";
                    }
                    if (root.known) {
                        return "";
                    }
                    return "Pair";
                }
                visible: !!text
                font.pixelSize: 10
                color: {
                    if (root.device.connected) {
                        return Theme.green;
                    }
                    if (root.known) {
                        return Theme.overlay1;
                    }
                    return Theme.blue;
                }
            }
            // Forget, behind the arrow
            IconButton {
                visible: root.known
                implicitHeight: Modes.touch ? 30 : 22
                glyph: Theme.glyph(root.expanded ? 0xf0143 : 0xf0140) // 󰅃 / 󰅀
                onClicked: root.toggleExpanded()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: root.expanded && root.known
            spacing: 6

            Label {
                Layout.fillWidth: true
                text: root.device.address
                font.pixelSize: 10
                color: Theme.overlay1
            }
            IconButton {
                glyph: Theme.glyph(0xf01b4) // 󰆴
                text: "Forget"
                onClicked: root.device.forget()
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: !!root.error
            text: root.error
            font.pixelSize: 10
            color: Theme.red
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
    }
}
