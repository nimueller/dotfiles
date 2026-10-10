import QtQuick
import QtQuick.Layouts

// One event of the selected day: calendar colour, time, title, location.
// One-off Nextcloud events can be edited and deleted (hover; delete asks
// to confirm).
Rectangle {
    id: root

    required property var event // { title, location, allDay, start: Date, end: Date }
    required property date day
    property color colour: Theme.lavender
    property bool editable: false
    property bool confirming: false

    signal editRequested
    signal deleteRequested

    function clock(d) {
        return Qt.formatTime(d, "HH:mm");
    }

    readonly property string when: {
        if (event.allDay)
            return "All day";
        const dayStart = new Date(day.getFullYear(), day.getMonth(), day.getDate());
        const dayEnd = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
        const from = event.start < dayStart ? "…" : clock(event.start);
        const to = event.end > dayEnd ? "…" : clock(event.end);
        return +event.end === +event.start ? from : `${from} – ${to}`;
    }

    implicitHeight: row.implicitHeight + 14
    radius: 8
    color: Qt.tint(Theme.alpha(Theme.surface0, hover.hovered ? 0.8 : 0.5), Theme.alpha(colour, 0.1))

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered) root.confirming = false
    }

    RowLayout {
        id: row

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 8
            rightMargin: 12
        }
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 3
            Layout.fillHeight: true
            radius: 2
            color: root.colour
        }
        Label {
            Layout.preferredWidth: 96
            Layout.alignment: Qt.AlignTop
            text: root.when
            font.pixelSize: 11
            color: Theme.subtext0
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Label {
                Layout.fillWidth: true
                text: root.event.title
            }
            Label {
                Layout.fillWidth: true
                visible: !!root.event.location
                text: `${Theme.glyph(0xf034e)} ${root.event.location}` // 󰍎
                font.pixelSize: 10
                color: Theme.overlay1
            }
            Label {
                Layout.fillWidth: true
                visible: (root.event.alarms ?? []).length > 0
                text: `${Theme.glyph(0xf009a)} ${(root.event.alarms ?? []).map(m => Reminders.describe(m)).join(", ")}` // 󰂚
                font.pixelSize: 10
                color: Theme.overlay1
            }
        }
        IconButton {
            visible: root.editable && hover.hovered && !root.confirming
            glyph: Theme.glyph(0xf03eb) // 󰏫
            onClicked: root.editRequested()
        }
        IconButton {
            visible: root.editable && (hover.hovered || root.confirming)
            glyph: Theme.glyph(0xf01b4) // 󰆴
            text: root.confirming ? "Delete?" : ""
            accent: Theme.red
            active: root.confirming
            onClicked: {
                if (root.confirming)
                    root.deleteRequested();
                root.confirming = !root.confirming;
            }
        }
    }
}
