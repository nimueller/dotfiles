import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// One notification popping up, in the bar's look: a crust card with a thin
// outline, the urgency as a tinted icon chip, and a bar along the bottom
// counting down until it hides (paused while hovered; critical ones stay).
// Left click: its default action (or focus the app), right click or ✕:
// close, middle click: close all.
Rectangle {
    id: root

    required property var entry
    signal activated
    signal closed
    signal closeAll
    signal action(string identifier)

    readonly property var n: entry.n
    readonly property bool critical: entry.urgency === 2
    readonly property color accent: critical ? Theme.red : entry.urgency === 0 ? Theme.overlay2 : Theme.lavender
    // Seconds, from the app or by urgency
    readonly property real timeout: critical ? 0 : n && n.expireTimeout > 0 ? n.expireTimeout : [5, 8, 0][entry.urgency]
    readonly property var progress: n?.hints?.value ?? null
    readonly property var actions: (n?.actions ?? []).filter(a => a.identifier !== "default")
    readonly property bool hovered: hover.hovered
    property real remaining: 1 // share of the timeout left

    // Fade out, then report what happened
    function leave(then) {
        if (outro.running)
            return;
        outro.then = then;
        outro.start();
    }

    implicitHeight: content.implicitHeight + 32
    radius: 14
    color: Theme.crust
    border.width: 1
    border.color: critical ? Theme.alpha(Theme.red, 0.7) : hovered ? Theme.surface1 : Theme.surface0

    Behavior on border.color { ColorAnimation { duration: 150 } }

    // Slide in from the right, fade out to the right
    transform: Translate { id: slide }
    Component.onCompleted: intro.start()
    ParallelAnimation {
        id: intro
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 180 }
        NumberAnimation { target: slide; property: "x"; from: 48; to: 0; duration: 260; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: outro
        property var then: null
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 160 }
            NumberAnimation { target: slide; property: "x"; to: 32; duration: 160; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                if (outro.then)
                    outro.then();
            }
        }
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.RightButton)
                root.leave(root.closed);
            else if (event.button === Qt.MiddleButton)
                root.closeAll();
            else
                root.leave(root.activated);
        }
    }

    RowLayout {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 14
        }
        spacing: 12

        // Icon on a chip tinted with the urgency colour
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: 12
            color: Theme.alpha(root.accent, 0.15)

            IconImage {
                id: icon
                anchors.centerIn: parent
                implicitSize: 30
                source: root.entry.icon
                asynchronous: true
                visible: !!root.entry.icon && status === Image.Ready
            }
            Label {
                anchors.centerIn: parent
                visible: !icon.visible
                text: Theme.glyph(root.critical ? 0xf0026 : 0xf009a) // 󰀦 / 󰂚
                font.pixelSize: 20
                color: root.accent
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            // App and close
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    Layout.fillWidth: true
                    text: root.entry.app || "Notification"
                    font.pixelSize: 10
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                    color: root.critical ? Theme.red : Theme.overlay1
                }
                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 9
                    opacity: root.hovered ? 1 : 0
                    color: closeMouse.containsMouse ? Theme.alpha(Theme.red, 0.2) : Theme.surface0

                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Label {
                        anchors.centerIn: parent
                        text: Theme.glyph(0xf0156) // 󰅖
                        font.pixelSize: 10
                        color: closeMouse.containsMouse ? Theme.red : Theme.overlay2
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.leave(root.closed)
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: root.n?.summary ?? root.entry.summary
                font.pixelSize: 13
                font.bold: true
                color: Theme.text
            }
            Label {
                Layout.fillWidth: true
                visible: !!text
                text: root.n?.body ?? root.entry.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 4
                color: Theme.subtext0
                linkColor: Theme.blue
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // Progress (copy jobs, ...)
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
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
                Layout.topMargin: 4
                visible: root.actions.length > 0
                spacing: 6

                Repeater {
                    model: root.actions

                    delegate: IconButton {
                        required property var modelData

                        text: modelData.text
                        accent: root.accent
                        onClicked: root.leave(() => root.action(modelData.identifier))
                    }
                }
            }
        }
    }

    // Time left until it hides
    Rectangle {
        id: countdown

        // Inset so it stays inside the rounded corners
        visible: root.timeout > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.bottomMargin: 4
        height: 3
        radius: 1.5
        width: (parent.width - 24) * root.remaining
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.lavender }
            GradientStop { position: 1; color: Theme.mauve }
        }

    }

    NumberAnimation on remaining {
        from: 1
        to: 0
        duration: root.timeout * 1000
        running: root.timeout > 0
        paused: running && root.hovered
        onFinished: root.leave(root.closed)
    }
}
