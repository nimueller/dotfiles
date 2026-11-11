import QtQuick
import QtQuick.Layouts

// A question from the pairing agent (BluetoothAgent.qml) in the Bluetooth
// menu: a code to compare, type or enter, or a device that wants to pair or
// connect by itself.
Rectangle {
    id: root

    required property var request

    readonly property string kind: request.kind
    readonly property string name: request.name || request.address
    readonly property bool typing: kind === "pin" || kind === "passkey"
    readonly property string value: field.text.trim()
    readonly property bool valid: {
        if (kind === "pin") {
            return value.length >= 1 && value.length <= 16;
        }
        if (kind === "passkey") {
            return /^\d{1,6}$/.test(value);
        }
        return true;
    }

    function accept() {
        if (valid) {
            BluetoothAgent.answer(request.id, true, value);
        }
    }

    implicitHeight: column.implicitHeight + 24
    radius: 10
    color: Theme.alpha(Theme.blue, 0.08)
    border.width: 1
    border.color: Theme.alpha(Theme.blue, 0.35)

    Component.onCompleted: if (typing) {
        field.focusField();
    }

    ColumnLayout {
        id: column

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: Theme.glyph(root.kind === "service" ? 0xf00b1 : 0xf00af) // 󰂱 / 󰂯
                font.pixelSize: 14
                color: Theme.blue
            }
            Label {
                Layout.fillWidth: true
                text: root.name
                font.bold: true
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: Theme.subtext0
            text: {
                switch (root.kind) {
                case "confirm":
                    return I18n.tr("Does it show this code too? Only pair if it does.");
                case "display":
                    return I18n.tr("Type this code on it, then press Enter there.");
                case "pin":
                    return I18n.tr("Asks for a PIN: the one in its manual (often 0000 or 1234), or for a keyboard any digits, then type them on it too.");
                case "passkey":
                    return I18n.tr("Enter the code it shows.");
                case "authorize":
                    return I18n.tr("Wants to pair with this computer.");
                case "service":
                    return I18n.tr("Wants to connect for %1. Allowed, it may from now on.", root.request.service);
                }
                return "";
            }
        }

        // The code to compare or type there; what's typed already in green
        Row {
            Layout.alignment: Qt.AlignHCenter
            visible: !!root.request.code
            spacing: 6

            Repeater {
                model: (root.request.code ?? "").split("")

                delegate: Label {
                    required property string modelData
                    required property int index

                    text: modelData
                    font.pixelSize: 24
                    font.bold: true
                    color: root.kind === "display" && index < (root.request.entered ?? 0) ? Theme.green : Theme.text
                }
            }
        }

        InputField {
            id: field

            Layout.fillWidth: true
            visible: root.typing
            accent: Theme.blue
            placeholder: root.kind === "pin" ? "PIN" : I18n.tr("6-digit code")
            onAccepted: root.accept()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Item {
                Layout.fillWidth: true
            }
            IconButton {
                text: {
                    if (root.kind === "display") {
                        return I18n.tr("Hide");
                    }
                    if (root.kind === "service") {
                        return I18n.tr("Deny");
                    }
                    return I18n.tr("Cancel");
                }
                onClicked: BluetoothAgent.answer(root.request.id, false)
            }
            IconButton {
                visible: root.kind !== "display"
                glyph: Theme.glyph(0xf012c) // 󰄬
                text: root.kind === "service" ? I18n.tr("Allow") : I18n.tr("Pair")
                accent: Theme.green
                active: root.valid
                onClicked: root.accept()
            }
        }
    }
}
