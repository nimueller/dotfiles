import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// One media player (MPRIS) in the sound menu:
//   [cover]  title / artist / player     ⏮ ⏯ ⏭
//   position slider                     0:42 / 3:07
// The cover falls back to the player's icon; without a length (streams) there
// is no slider. Click the cover to bring the player's window up.
Rectangle {
    id: root

    required property var player // MprisPlayer
    property color accent: Theme.lavender

    readonly property bool hasLength: (player?.lengthSupported ?? false) && player.length > 0

    implicitHeight: column.implicitHeight + 20
    radius: 10
    color: Theme.mantle

    // MPRIS doesn't announce the position while it moves
    Timer {
        running: root.visible && (root.player?.isPlaying ?? false) && root.hasLength
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: 8
                color: Theme.alpha(root.accent, 0.15)
                clip: true

                Label {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready && !appIcon.visible
                    text: Theme.glyph(0xf075a) // 󰝚
                    font.pixelSize: 22
                    color: root.accent
                }
                IconImage {
                    id: appIcon
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready && !!source
                    source: Media.icon(root.player)
                    implicitSize: 32
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 104
                    sourceSize.height: 104
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.player?.canRaise ?? false
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.raise()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: Media.title(root.player)
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    visible: !!text
                    text: Media.artist(root.player)
                    color: Theme.subtext0
                    font.pixelSize: 11
                }
                Label {
                    Layout.fillWidth: true
                    visible: !!root.player?.trackTitle
                    text: Media.name(root.player)
                    color: Theme.overlay1
                    font.pixelSize: 10
                }
            }

            IconButton {
                enabled: root.player?.canGoPrevious ?? false
                opacity: enabled ? 1 : 0.4
                glyph: Theme.glyph(0xf04ae) // 󰒮
                onClicked: root.player.previous()
            }
            IconButton {
                enabled: root.player?.canTogglePlaying ?? false
                active: true
                accent: root.accent
                glyph: Theme.glyph(root.player?.isPlaying ? 0xf03e4 : 0xf040a) // 󰏤 / 󰐊
                onClicked: root.player.togglePlaying()
            }
            IconButton {
                enabled: root.player?.canGoNext ?? false
                opacity: enabled ? 1 : 0.4
                glyph: Theme.glyph(0xf04ad) // 󰒭
                onClicked: root.player.next()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.hasLength
            spacing: 10

            Slider {
                Layout.fillWidth: true
                accent: root.accent
                value: root.hasLength ? Math.min(1, root.player.position / root.player.length) : 0
                onMoved: v => {
                    if (root.player?.canSeek)
                        root.player.position = v * root.player.length;
                }
            }
            Label {
                text: `${Media.time(root.player?.position ?? 0)} / ${Media.time(root.player?.length ?? 0)}`
                color: Theme.subtext1
                font.pixelSize: 11
                font.features: { "tnum": 1 }
            }
        }
    }
}
