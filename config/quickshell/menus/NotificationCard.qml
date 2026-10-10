import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// One entry of the notification center. Click to act on it (default action
// or focus the app), ✕ to remove it.
Rectangle {
    id: root

    required property var entry
    required property real now // ms, for the age
    readonly property var n: entry.n
    readonly property bool critical: entry.urgency === 2

    signal activated
    signal dismissed

    implicitHeight: row.implicitHeight + 20
    radius: 10
    color: mouse.containsMouse ? Theme.surface0 : Theme.alpha(Theme.surface0, 0.5)
    border.width: critical ? 1 : 0
    border.color: Theme.alpha(Theme.red, 0.6)

    Behavior on color { ColorAnimation { duration: 120 } }

    function age(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        if (s < 60)
            return "now";
        if (s < 3600)
            return `${Math.floor(s / 60)}m`;
        if (s < 86400)
            return `${Math.floor(s / 3600)}h`;
        return `${Math.floor(s / 86400)}d`;
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    RowLayout {
        id: row

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 8
            color: Theme.alpha(root.critical ? Theme.red : Theme.lavender, 0.15)

            IconImage {
                id: icon
                anchors.centerIn: parent
                implicitSize: 24
                source: root.entry.icon
                visible: !!root.entry.icon && status === Image.Ready
            }
            Label {
                anchors.centerIn: parent
                visible: !icon.visible
                text: Theme.glyph(0xf009a) // 󰂚
                font.pixelSize: 16
                color: root.critical ? Theme.red : Theme.lavender
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    Layout.fillWidth: true
                    text: root.n?.summary ?? root.entry.summary ?? root.entry.app
                    font.bold: true
                    color: root.critical ? Theme.red : Theme.text
                }
                Label {
                    text: root.age(root.now - root.entry.time)
                    font.pixelSize: 10
                    color: Theme.overlay0
                }

                // Remove
                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 9
                    color: closeMouse.containsMouse ? Theme.alpha(Theme.red, 0.2) : "transparent"
                    opacity: mouse.containsMouse || closeMouse.containsMouse ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Label {
                        anchors.centerIn: parent
                        text: Theme.glyph(0xf0156) // 󰅖
                        font.pixelSize: 11
                        color: closeMouse.containsMouse ? Theme.red : Theme.overlay1
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissed()
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: root.entry.app
                font.pixelSize: 10
                color: Theme.overlay1
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: !!text
                text: root.n?.body ?? root.entry.body ?? ""
                textFormat: Text.StyledText
                color: Theme.subtext0
                linkColor: Theme.blue
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: 3
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
