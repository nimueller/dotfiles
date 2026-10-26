import QtQuick

// Text field with a placeholder; `masked` for passwords and one-time codes,
// with an eye to show what's typed. typed() fires only for typing, not
// when `text` is set.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property bool masked: false
    property bool revealed: false
    property color accent: Theme.sapphire

    signal accepted
    signal typed

    function focusField() {
        input.forceActiveFocus();
    }

    implicitHeight: 28
    radius: 8
    color: Theme.mantle
    border.width: 1
    border.color: input.activeFocus ? accent : Theme.surface1

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: root.masked ? 30 : 10
        verticalAlignment: TextInput.AlignVCenter
        echoMode: root.masked && !root.revealed ? TextInput.Password : TextInput.Normal
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 12
        clip: true
        onAccepted: root.accepted()
        onTextEdited: root.typed()

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            text: root.placeholder
            color: Theme.overlay0
        }
    }

    // Show or hide the password
    Label {
        visible: root.masked
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: Theme.glyph(root.revealed ? 0xf0209 : 0xf0208) // 󰈉 / 󰈈
        font.pixelSize: 14
        color: eye.containsMouse || root.revealed ? root.accent : Theme.overlay1

        MouseArea {
            id: eye

            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.revealed = !root.revealed;
                input.forceActiveFocus();
            }
        }
    }
}
