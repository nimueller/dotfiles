import QtQuick
import QtQuick.Layouts

// One Wi-Fi network. Click to connect (open or saved networks) or to expand
// it for a password / disconnect / forget.
Rectangle {
    id: root

    required property var network // { ssid, signal, secure, active, known }
    property bool expanded: false
    property bool busy: false
    property string error: ""

    signal clicked
    signal connectRequested(string password)
    signal disconnectRequested
    signal forgetRequested

    readonly property bool needsPassword: network.secure && !network.known && !network.active

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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                visible: root.needsPassword
                radius: 8
                color: Theme.mantle
                border.width: 1
                border.color: password.activeFocus ? Theme.sapphire : Theme.surface1

                TextInput {
                    id: password

                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12
                    clip: true
                    onAccepted: if (text) root.connectRequested(text)

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !password.text
                        text: "Password"
                        color: Theme.overlay0
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                visible: !root.needsPassword
            }
            IconButton {
                visible: root.network.active
                glyph: Theme.glyph(0xf0318) // 󰌘
                text: "Disconnect"
                onClicked: root.disconnectRequested()
            }
            IconButton {
                visible: !root.network.active
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

        onVisibleChanged: if (root.expanded && root.needsPassword) password.forceActiveFocus()
    }

    onExpandedChanged: if (expanded && needsPassword) password.forceActiveFocus()
}
