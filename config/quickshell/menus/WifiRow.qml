import QtQuick
import QtQuick.Layouts

// One Wi-Fi network. Click to connect (open or saved networks) or to expand
// it for a password / disconnect / forget. Enterprise networks (802.1X) need
// a user name too: Set up opens the connection editor.
Rectangle {
    id: root

    required property var network // { ssid, signal, secure, enterprise, active, known }
    property bool expanded: false
    property bool busy: false
    property bool askPassword: false // the saved password didn't work
    property string error: ""

    signal clicked
    signal connectRequested(string password)
    signal setupRequested
    signal disconnectRequested
    signal forgetRequested

    readonly property bool setup: network.enterprise && !network.known && !network.active
    readonly property bool needsPassword: network.secure && !setup && !network.active && (!network.known || askPassword)

    implicitHeight: column.implicitHeight + 12
    radius: 8
    color: expanded ? Theme.surface0 : mouse.containsMouse ? Theme.alpha(Theme.surface0, 0.6) : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }

    function signalGlyph(s) {
        return Theme.glyph(s > 75 ? 0xf0928 : s > 50 ? 0xf0925 : s > 25 ? 0xf0922 : 0xf091f); // 󰤨 󰤥 󰤢 󰤟
    }

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
            margins: 6
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 10

            Label {
                Layout.preferredWidth: 16
                text: root.signalGlyph(root.network.signal)
                color: root.network.active ? Theme.sapphire : Theme.overlay2
            }
            Label {
                Layout.fillWidth: true
                text: root.network.ssid
                color: root.network.active ? Theme.text : Theme.subtext1
                font.bold: root.network.active
            }
            Label {
                visible: root.busy || root.network.active || root.network.known
                text: root.busy ? "Connecting…" : root.network.active ? "Connected" : "Saved"
                font.pixelSize: 10
                color: root.network.active ? Theme.green : Theme.overlay1
            }
            Label {
                visible: root.network.secure
                text: Theme.glyph(0xf033e) // 󰌾
                font.pixelSize: 11
                color: Theme.overlay0
            }
        }

        // Details: password field or connection actions
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: root.expanded
            spacing: 6

            InputField {
                id: password

                Layout.fillWidth: true
                visible: root.needsPassword
                masked: true
                placeholder: "Password"
                onAccepted: if (text) root.connectRequested(text)
            }
            Item {
                Layout.fillWidth: true
                visible: !root.needsPassword && !root.setup
            }
            IconButton {
                visible: root.network.active
                glyph: Theme.glyph(0xf0318) // 󰌘
                text: "Disconnect"
                onClicked: root.disconnectRequested()
            }
            Label {
                Layout.fillWidth: true
                visible: root.setup
                text: "Needs a user name and password"
                font.pixelSize: 10
                color: Theme.overlay1
            }
            IconButton {
                visible: root.setup
                glyph: Theme.glyph(0xf0493) // 󰒓
                text: "Set up"
                accent: Theme.sapphire
                active: true
                onClicked: root.setupRequested()
            }
            IconButton {
                visible: !root.network.active && !root.setup
                glyph: Theme.glyph(0xf0317) // 󰌗
                text: "Connect"
                accent: Theme.sapphire
                active: true
                onClicked: {
                    if (!root.needsPassword || password.text)
                        root.connectRequested(password.text);
                }
            }
            IconButton {
                visible: root.network.known
                glyph: Theme.glyph(0xf01b4) // 󰆴
                text: "Forget"
                onClicked: root.forgetRequested()
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: root.expanded && !!root.error
            text: root.error
            font.pixelSize: 10
            color: Theme.red
            wrapMode: Text.Wrap
        }

        onVisibleChanged: if (root.expanded && root.needsPassword) password.focusField()
    }

    onExpandedChanged: if (expanded && needsPassword) password.focusField()
}
