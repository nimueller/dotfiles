import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// [mute button]  (title / subtitle)  slider  42%
RowLayout {
    id: root

    required property PwNode node
    property color accent: Theme.blue
    property string glyph: ""
    property string iconSource: ""
    property string title: ""
    property string subtitle: ""

    readonly property bool muted: node?.audio?.muted ?? false

    spacing: 10

    Rectangle {
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        radius: 8
        color: root.muted ? Theme.surface0 : Theme.alpha(root.accent, muteMouse.containsMouse ? 0.25 : 0.15)

        Behavior on color { ColorAnimation { duration: 150 } }

        Label {
            anchors.centerIn: parent
            visible: !root.iconSource
            text: root.glyph
            font.pixelSize: 16
            color: root.muted ? Theme.overlay0 : root.accent
        }

        IconImage {
            anchors.centerIn: parent
            visible: !!root.iconSource
            source: root.iconSource
            implicitSize: 20
            opacity: root.muted ? 0.35 : 1
        }

        MouseArea {
            id: muteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.node?.audio)
                    root.node.audio.muted = !root.node.audio.muted;
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            visible: !!root.title
            spacing: 6

            Label {
                text: root.title
                color: root.muted ? Theme.overlay1 : Theme.text
            }
            Label {
                Layout.fillWidth: true
                text: root.subtitle
                color: Theme.overlay1
                font.pixelSize: 11
            }
        }

        VolumeSlider {
            Layout.fillWidth: true
            node: root.node
            accent: root.accent
        }
    }

    Label {
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
        text: root.muted ? "muted" : `${Math.round((root.node?.audio?.volume ?? 0) * 100)}%`
        color: root.muted ? Theme.overlay0 : Theme.subtext1
        font.pixelSize: 11
    }
}
