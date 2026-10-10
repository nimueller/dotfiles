import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

// Volume of the default sink/source plus a dropdown to switch devices.
ColumnLayout {
    id: root

    required property string title
    required property bool output
    property color accent: Theme.blue
    property bool expanded: false

    readonly property PwNode current: output ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
    readonly property var devices: output ? Audio.sinks : Audio.sources
    readonly property var others: devices.filter(n => n !== current)

    spacing: 8

    SectionTitle {
        text: root.title
    }

    VolumeRow {
        Layout.fillWidth: true
        visible: !!root.current
        node: root.current
        accent: root.accent
        glyph: root.output ? Audio.volumeIcon(root.current?.audio) : Audio.micIcon(root.current?.audio)
    }

    // Current device; click to pick another one
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        radius: 8
        color: pickerMouse.containsMouse && root.others.length > 0 ? Theme.surface1 : Theme.surface0

        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Label {
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
                text: Audio.deviceIcon(root.current)
                color: root.accent
            }
            Label {
                Layout.fillWidth: true
                text: Audio.deviceName(root.current)
                color: Theme.subtext1
            }
            Label {
                visible: root.others.length > 0
                text: Audio.glyph(root.expanded ? 0xf0143 : 0xf0140) // 󰅃 / 󰅀
                color: Theme.overlay1
            }
        }

        MouseArea {
            id: pickerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.others.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.expanded = root.others.length > 0 && !root.expanded
        }
    }

    Repeater {
        model: root.expanded ? root.others : []

        delegate: Rectangle {
            id: option

            required property PwNode modelData

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Layout.leftMargin: 8
            radius: 8
            color: optionMouse.containsMouse ? Theme.alpha(root.accent, 0.15) : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Label {
                    Layout.preferredWidth: 16
                    horizontalAlignment: Text.AlignHCenter
                    text: Audio.deviceIcon(option.modelData)
                    color: optionMouse.containsMouse ? root.accent : Theme.overlay1
                }
                Label {
                    Layout.fillWidth: true
                    text: Audio.deviceName(option.modelData)
                    color: optionMouse.containsMouse ? Theme.text : Theme.subtext0
                }
            }

            MouseArea {
                id: optionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Audio.setDefault(option.modelData);
                    root.expanded = false;
                }
            }
        }
    }
}
