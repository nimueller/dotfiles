// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell

// Phone menu for the bar's phone module, on top of KDE Connect
// (kdeconnect.py): battery and mobile network of each paired phone, and
// ring it, send files or the clipboard, ping it, browse its files in Files.
// The gear opens the KDE Connect app (pairing, plugins).
Popup {
    id: popup

    name: "kdeconnect"
    cardWidth: 340

    readonly property var actions: [
        { action: "ring", text: "Ring", glyph: 0xf009e, accent: Theme.peach }, // 󰂞
        { action: "send", text: "Send files", glyph: 0xf0552, accent: Theme.blue }, // 󰕒
        { action: "clipboard", text: "Send clipboard", glyph: 0xf014c, accent: Theme.mauve }, // 󰅌
        { action: "browse", text: "Browse files", glyph: 0xf024b, accent: Theme.teal }, // 󰉋
        { action: "ping", text: "Ping", glyph: 0xf0437, accent: Theme.lavender } // 󰐷
    ]

    PhoneStatus {
        id: phones
    }

    Header {
        glyph: Theme.glyph(0xf011c) // 󰄜
        accent: Theme.teal
        title: "Phone"

        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            onClicked: {
                Quickshell.execDetached(["kdeconnect-app"]);
                popup.close();
            }
        }
    }

    Label {
        visible: phones.devices.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "No paired phone. Pair one in the KDE Connect app (the gear) and on the phone."
        color: Theme.subtext0
    }

    Repeater {
        model: phones.devices

        delegate: ColumnLayout {
            id: device

            required property var modelData

            Layout.fillWidth: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: device.modelData.name
                    font.bold: true
                    color: device.modelData.reachable ? Theme.text : Theme.overlay1
                    elide: Text.ElideRight
                }
                Label {
                    visible: !device.modelData.reachable
                    text: "Not connected"
                    color: Theme.overlay1
                }
                Label {
                    visible: device.modelData.reachable && !!device.modelData.network
                    text: `${Theme.glyph([0xf08bf, 0xf08bc, 0xf08bd, 0xf08be, 0xf08be][Math.max(0, Math.min(4, device.modelData.signal))])}  ${device.modelData.network}` // 󰢿 󰢼 󰢽 󰢾
                    color: Theme.subtext0
                }
                Label {
                    readonly property int charge: device.modelData.battery

                    visible: device.modelData.reachable && charge >= 0
                    text: `${Theme.glyph(device.modelData.charging ? 0xf0084 : [0xf008e, 0xf007b, 0xf007d, 0xf007f, 0xf0081, 0xf0079][Math.min(5, Math.floor(charge / 20))])}  ${charge}%` // 󰂄 / 󰂎…󰁹
                    color: device.modelData.charging ? Theme.teal : charge <= 15 ? Theme.red : charge <= 30 ? Theme.yellow : Theme.green
                }
            }

            GridLayout {
                visible: device.modelData.reachable
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 6
                columnSpacing: 6

                Repeater {
                    model: popup.actions

                    delegate: Rectangle {
                        id: tile

                        required property var modelData
                        required property int index

                        // The last one alone in its row spans both columns
                        Layout.columnSpan: index === popup.actions.length - 1 && popup.actions.length % 2 ? 2 : 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 8
                        color: tileMouse.containsMouse ? Theme.alpha(modelData.accent, 0.22) : Theme.surface0

                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Label {
                                text: Theme.glyph(tile.modelData.glyph)
                                color: tile.modelData.accent
                            }
                            Label {
                                Layout.fillWidth: true
                                text: tile.modelData.text
                                color: tileMouse.containsMouse ? Theme.text : Theme.subtext1
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                phones.run(tile.modelData.action, device.modelData);
                                popup.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
