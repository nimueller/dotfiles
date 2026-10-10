import QtQuick
import QtQuick.Layouts

// One VPN connection: switch to connect/disconnect, click to expand for
// edit / remove, or for the password when the VPN needs one.
Rectangle {
    id: root

    required property var vpn // { name, uuid, kind, state, address, needsPassword, hasChallenge }
    property bool expanded: false
    property bool busy: false
    property string error: ""

    signal clicked
    signal toggled
    signal connectRequested(string password, string code)
    signal editRequested
    signal removeRequested

    readonly property bool active: vpn.state === "activated"
    readonly property bool activating: busy || vpn.state === "activating"
    readonly property bool askPassword: expanded && vpn.needsPassword && !active
    property bool confirmRemove: false

    onExpandedChanged: {
        confirmRemove = false;
        if (askPassword)
            password.focusField();
    }

    function connectWithFields() {
        if (password.text)
            root.connectRequested(password.text, code.text);
    }

    implicitHeight: column.implicitHeight + 16
    radius: 10
    color: expanded ? Theme.surface0 : Theme.alpha(Theme.surface0, mouse.containsMouse ? 0.8 : 0.5)

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: column

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 8
            rightMargin: 12
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: root.active ? Theme.alpha(Theme.green, 0.15) : Theme.surface0

                Label {
                    anchors.centerIn: parent
                    text: Theme.glyph(0xf099d) // 󰦝
                    font.pixelSize: 16
                    color: root.active ? Theme.green : Theme.overlay0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: root.vpn.name
                    color: root.active ? Theme.text : Theme.subtext0
                }
                Label {
                    Layout.fillWidth: true
                    font.pixelSize: 10
                    color: Theme.overlay1
                    text: {
                        const state = root.activating ? "connecting…" : root.active ? "connected" : "off";
                        return [root.vpn.kind, state, root.active ? root.vpn.address : ""].filter(x => x).join(" · ");
                    }
                }
            }

            Switch {
                checked: root.active || root.activating
                accent: Theme.green
                onToggled: root.toggled()
            }
        }

        // Password (and one-time code) for VPNs that don't store them
        PasswordField {
            id: password
            Layout.fillWidth: true
            visible: root.askPassword
            placeholder: "Password"
            accent: Theme.green
            onAccepted: root.connectWithFields()
        }
        PasswordField {
            id: code
            Layout.fillWidth: true
            visible: root.askPassword && root.vpn.hasChallenge
            placeholder: "One-time code (if required)"
            accent: Theme.green
            onAccepted: root.connectWithFields()
        }

        // Edit / remove, or connect with the password above
        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 6

            IconButton {
                glyph: Theme.glyph(0xf03eb) // 󰏫
                text: "Edit"
                onClicked: root.editRequested()
            }
            IconButton {
                glyph: Theme.glyph(0xf01b4) // 󰆴
                text: root.confirmRemove ? "Really remove?" : "Remove"
                accent: Theme.red
                active: root.confirmRemove
                onClicked: {
                    if (root.confirmRemove)
                        root.removeRequested();
                    root.confirmRemove = !root.confirmRemove;
                }
            }
            Item {
                Layout.fillWidth: true
            }
            IconButton {
                visible: root.askPassword
                glyph: Theme.glyph(0xf0317) // 󰌗
                text: "Connect"
                accent: Theme.green
                active: true
                onClicked: root.connectWithFields()
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.expanded && !!root.error
            text: root.error
            font.pixelSize: 10
            color: Theme.red
            wrapMode: Text.Wrap
        }
    }
}
