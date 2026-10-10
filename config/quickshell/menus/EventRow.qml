import QtQuick
import QtQuick.Layouts

// One event of the selected day: calendar colour, time, title, location.
Rectangle {
    id: root

    required property var event // { title, location, allDay, start: Date, end: Date }
    required property date day
    property color colour: Theme.lavender

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
    color: Theme.alpha(Theme.surface0, 0.5)

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
        }
    }
}
