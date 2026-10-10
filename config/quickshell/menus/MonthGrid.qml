import QtQuick
import QtQuick.Layouts

// Month view: weeks start on Monday with ISO week numbers on the left,
// today filled, the selected day outlined, one dot per calendar with events
// that day. Scroll to change the month.
ColumnLayout {
    id: root

    required property int year
    required property int month // 0-11
    required property date today
    required property date selected
    property var dots: ({}) // "yyyy-MM-dd" -> [colour, ...]

    signal picked(date day)
    signal shift(int months)
    signal reset

    // Monday on or before the 1st
    readonly property date first: {
        const d = new Date(year, month, 1);
        return new Date(year, month, 1 - (d.getDay() + 6) % 7);
    }
    readonly property bool showingToday: year === today.getFullYear() && month === today.getMonth() && sameDay(selected, today)

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function isoWeek(d) {
        const thursday = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3 - (d.getDay() + 6) % 7);
        const jan4 = new Date(thursday.getFullYear(), 0, 4);
        return 1 + Math.round(((thursday - jan4) / 86400000 - 3 + (jan4.getDay() + 6) % 7) / 7);
    }

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Label {
            Layout.fillWidth: true
            text: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")
            font.pixelSize: 13
            font.bold: true
        }
        IconButton {
            visible: !root.showingToday
            glyph: Theme.glyph(0xf00f6) // 󰃶
            text: "Today"
            onClicked: root.reset()
        }
        IconButton {
            glyph: Theme.glyph(0xf0141) // 󰅁
            onClicked: root.shift(-1)
        }
        IconButton {
            glyph: Theme.glyph(0xf0142) // 󰅂
            onClicked: root.shift(1)
        }
    }

    GridLayout {
        id: grid

        Layout.fillWidth: true
        columns: 8
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
            model: ["Wk", "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

            delegate: Label {
                required property string modelData
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: 22
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                font.pixelSize: 10
                font.bold: index > 0
                color: index === 0 ? Theme.overlay0 : index >= 6 ? Theme.overlay2 : Theme.subtext0
            }
        }

        Repeater {
            model: 6 * 8

            delegate: Item {
                id: cell

                required property int index
                readonly property int row: Math.floor(index / 8)
                readonly property int column: index % 8
                readonly property date day: new Date(root.first.getFullYear(), root.first.getMonth(), root.first.getDate() + row * 7 + Math.max(column - 1, 0))
                readonly property bool inMonth: day.getMonth() === root.month
                readonly property bool isToday: root.sameDay(day, root.today)
                readonly property bool isSelected: root.sameDay(day, root.selected)
                readonly property var colours: root.dots[Qt.formatDate(day, "yyyy-MM-dd")] ?? []

                Layout.fillWidth: true
                Layout.preferredHeight: 36

                // Week number
                Label {
                    anchors.centerIn: parent
                    visible: cell.column === 0
                    text: root.isoWeek(cell.day)
                    font.pixelSize: 10
                    color: Theme.overlay0
                }

                Rectangle {
                    id: bubble

                    visible: cell.column > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 2
                    width: 28
                    height: 26
                    radius: 8
                    color: cell.isToday ? Theme.lavender : cell.isSelected ? Theme.alpha(Theme.lavender, 0.14) : mouse.containsMouse ? Theme.surface0 : "transparent"
                    border.width: cell.isSelected && !cell.isToday ? 1 : 0
                    border.color: Theme.lavender

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Label {
                        anchors.centerIn: parent
                        text: cell.day.getDate()
                        font.bold: cell.isToday || cell.isSelected
                        color: cell.isToday ? Theme.crust : !cell.inMonth ? Theme.surface2 : cell.column >= 6 ? Theme.overlay2 : Theme.text
                    }
                }

                Row {
                    visible: cell.column > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: bubble.bottom
                    anchors.topMargin: 2
                    spacing: 2

                    Repeater {
                        model: cell.colours.slice(0, 3)

                        delegate: Rectangle {
                            required property string modelData

                            width: 4
                            height: 4
                            radius: 2
                            color: modelData
                            opacity: cell.inMonth ? 1 : 0.4
                        }
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    enabled: cell.column > 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(cell.day)
                }
            }
        }
    }

    WheelHandler {
        target: null
        onWheel: event => root.shift(event.angleDelta.y > 0 ? -1 : 1)
    }
}
