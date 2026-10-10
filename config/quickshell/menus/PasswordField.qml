import QtQuick

// Masked text field with a placeholder, for passwords and one-time codes.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property color accent: Theme.sapphire

    signal accepted

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
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        echoMode: TextInput.Password
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 12
        clip: true
        onAccepted: root.accepted()

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            text: root.placeholder
            color: Theme.overlay0
        }
    }
}
