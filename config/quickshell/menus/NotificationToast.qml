import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// One notification popping up. Left click: its default action (or focus the
// app), right click: close, middle click: close all. Hovering pauses the
// timeout; critical ones stay until closed.
Rectangle {
    id: root

    required property var entry
    signal activated
    signal closed
    signal closeAll
    signal action(string identifier)

    readonly property var n: entry.n
    readonly property color accent: [Theme.surface1, Theme.lavender, Theme.red][entry.urgency]
    // Seconds, from the app or by urgency (like the dunst config this replaces)
    readonly property real timeout: n && n.expireTimeout > 0 ? n.expireTimeout : [5, 8, 0][entry.urgency]
    readonly property var progress: n?.hints?.value ?? null
    readonly property var actions: (n?.actions ?? []).filter(a => a.identifier !== "default")

    implicitHeight: content.implicitHeight + 24
    radius: 10
    color: Theme.crust
    border.width: 2
    border.color: accent

    // Slide in from the right
    transform: Translate { id: slide }
    Component.onCompleted: intro.start()
    ParallelAnimation {
        id: intro
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 150 }
        NumberAnimation { target: slide; property: "x"; from: 40; to: 0; duration: 220; easing.type: Easing.OutCubic }
    }

    Timer {
        id: lifetime
        interval: root.timeout * 1000
        running: root.timeout > 0 && !mouse.containsMouse
        onTriggered: root.closed()
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.RightButton)
                root.closed();
            else if (event.button === Qt.MiddleButton)
                root.closeAll();
            else
                root.activated();
        }
    }

    ColumnLayout {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
            leftMargin: 14
            rightMargin: 14
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 8
                color: icon.visible ? "transparent" : Theme.alpha(root.accent, 0.15)

                IconImage {
                    id: icon
                    anchors.fill: parent
                    source: root.entry.icon
                    asynchronous: true
                    visible: !!root.entry.icon && status === Image.Ready
                }
                Label {
                    anchors.centerIn: parent
                    visible: !icon.visible
                    text: Theme.glyph(0xf009a) // 󰂚
                    font.pixelSize: 18
                    color: root.entry.urgency === 0 ? Theme.overlay2 : root.accent
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
                        text: root.n?.summary ?? root.entry.summary
                        font.bold: true
                        color: root.entry.urgency === 2 ? Theme.red : Theme.text
                    }
                    Label {
                        text: root.entry.app
                        font.pixelSize: 10
                        color: Theme.overlay1
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: !!text
                    text: root.n?.body ?? root.entry.body
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    color: root.entry.urgency === 0 ? Theme.subtext0 : Theme.subtext1
                    linkColor: Theme.blue
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
        }

        // Progress (volume, copy jobs, ...)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            visible: root.progress !== null
            radius: 3
            color: Theme.surface0

            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, root.progress ?? 0)) / 100
                height: parent.height
                radius: 3
                color: root.accent
            }
        }

        // Actions
        Flow {
            Layout.fillWidth: true
            visible: root.actions.length > 0
            spacing: 6

            Repeater {
                model: root.actions

                delegate: IconButton {
                    required property var modelData

                    text: modelData.text
                    accent: root.accent
                    onClicked: root.action(modelData.identifier)
                }
            }
        }
    }

    // Time left
    Rectangle {
        visible: root.timeout > 0
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: 2
        anchors.leftMargin: 10
        height: 2
        radius: 1
        color: Theme.alpha(root.accent, 0.6)
        width: (root.width - 20)

        NumberAnimation on width {
            from: root.width - 20
            to: 0
            duration: root.timeout * 1000
            running: root.timeout > 0
            paused: mouse.containsMouse
        }
    }
}
