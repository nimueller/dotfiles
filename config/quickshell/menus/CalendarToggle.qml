import QtQuick
import QtQuick.Layouts

// A calendar in the settings: colour, name, detail, on/off switch and,
// for subscriptions, a remove button (click twice).
RowLayout {
    id: root

    property string name: ""
    property color colour: Theme.lavender
    property string detail: ""
    property bool checked: true
    property bool removable: false
    property bool confirming: false

    signal toggled
    signal removed

    Layout.preferredHeight: 26
    spacing: 10

    Rectangle {
        Layout.preferredWidth: 10
        Layout.preferredHeight: 10
        radius: 5
        color: root.colour
    }
    Label {
        text: root.name
        color: root.checked ? Theme.text : Theme.overlay1
    }
    Label {
        Layout.fillWidth: true
        text: root.detail
        font.pixelSize: 10
        color: Theme.overlay0
    }
    IconButton {
        visible: root.removable
        glyph: Theme.glyph(0xf01b4) // 󰆴
        text: root.confirming ? "Remove?" : ""
        accent: Theme.red
        active: root.confirming
        onClicked: {
            if (root.confirming)
                root.removed();
            root.confirming = !root.confirming;
        }
    }
    Switch {
        checked: root.checked
        accent: root.colour
        onToggled: root.toggled()
    }
}
