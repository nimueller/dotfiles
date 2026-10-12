import QtQuick
import QtQuick.Layouts
import Quickshell

// Notification center for the bar's bell, part of daemon.qml: the history
// of the notification store, with do not disturb and clear all.
Popup {
    id: popup

    required property var store
    property real now: Date.now()

    name: "notifications"
    cardWidth: 400
    resident: true

    // Keep the ages fresh while open
    Timer {
        interval: 30 * 1000
        running: popup.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: popup.now = Date.now()
    }

    Header {
        glyph: Theme.glyph(popup.store.dnd ? 0xf009b : 0xf009a) // 󰂛 / 󰂚
        accent: popup.store.dnd ? Theme.overlay1 : Theme.lavender
        title: "Notifications"
        badge: popup.store.entries.length || ""

        IconButton {
            glyph: Theme.glyph(0xf009b) // 󰂛
            text: popup.store.dnd ? "Silenced" : "Silence"
            accent: Theme.peach
            active: popup.store.dnd
            onClicked: popup.store.setDnd(!popup.store.dnd)
        }
        IconButton {
            visible: popup.store.entries.length > 0
            glyph: Theme.glyph(0xf05e9) // 󰗩
            text: "Clear"
            onClicked: popup.store.clear()
        }
    }

    // Do-not-disturb banner
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        visible: popup.store.silenced
        radius: 8
        color: Theme.alpha(Theme.peach, 0.12)

        Label {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            text: popup.store.dnd ? "Do not disturb is on: notifications don't pop up" : "The screen is shared: notifications don't pop up"
            font.pixelSize: 11
            color: Theme.peach
        }
    }

    // Empty state
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        visible: popup.store.entries.length === 0
        spacing: 6

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: Theme.glyph(0xf009c) // 󰂜
            font.pixelSize: 32
            color: Theme.surface2
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "You're all caught up"
            color: Theme.overlay1
        }
    }

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 480)
        visible: popup.store.entries.length > 0
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: popup.store.entries

        delegate: NotificationCard {
            required property var modelData

            width: list.width
            entry: modelData
            now: popup.now
            onActivated: {
                popup.store.activate(modelData.key);
                popup.close();
            }
            onDismissed: popup.store.remove(modelData.key)
        }
    }
}
