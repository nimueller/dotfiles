import QtQuick
import QtQuick.Layouts

// Month view as a grid of day boxes: the day's forecast (glyph and high) and
// its appointments as coloured chips. Weeks start on `weekStart` (0 = Sunday,
// 1 = Monday, 6 = Saturday) with optional ISO week numbers. Click a day to
// select it, double-click to add an appointment, scroll to change the month.
// Click the month's name to pick any month and year.
ColumnLayout {
    id: root

    required property int year
    required property int month // 0-11
    required property date today
    required property date selected
    property int weekStart: 1
    property bool weekNumbers: true
    property var events: ({}) // "yyyy-MM-dd" -> [{ title, colour, allDay, start }]
    property var forecast: ({}) // "yyyy-MM-dd" -> { code, max, min, rain }
    property var legend: [] // calendars shown: [{ name, color }]

    signal picked(date day)
    signal activated(date day)
    signal shift(int months)
    signal reset
    signal jump(int year, int month)

    property bool picking: false // month/year picker shown instead of the days
    property int pickerYear: year

    readonly property date first: {
        const d = new Date(year, month, 1);
        return new Date(year, month, 1 - (d.getDay() - weekStart + 7) % 7);
    }
    readonly property bool showingToday: year === today.getFullYear() && month === today.getMonth() && sameDay(selected, today)
    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function addDays(d, n) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
    }

    // ISO week of the Monday in the row starting at `rowStart`
    function isoWeek(rowStart) {
        const monday = addDays(rowStart, (8 - rowStart.getDay()) % 7);
        const thursday = addDays(monday, 3);
        const jan4 = new Date(thursday.getFullYear(), 0, 4);
        return 1 + Math.round(((thursday - jan4) / 86400000 - 3 + (jan4.getDay() + 6) % 7) / 7);
    }

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        // Month and year: click to pick another
        Rectangle {
            implicitWidth: titleRow.implicitWidth + 16
            implicitHeight: 28
            radius: 8
            color: root.picking ? Theme.alpha(Theme.lavender, 0.18) : titleMouse.containsMouse ? Theme.surface0 : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
                id: titleRow
                anchors.centerIn: parent
                spacing: 6

                Label {
                    text: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")
                    font.pixelSize: 14
                    font.bold: true
                    color: root.picking ? Theme.lavender : Theme.text
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.glyph(root.picking ? 0xf0143 : 0xf0140) // 󰅃 / 󰅀
                    font.pixelSize: 11
                    color: titleMouse.containsMouse || root.picking ? Theme.lavender : Theme.overlay1
                }
            }
            MouseArea {
                id: titleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.pickerYear = root.year;
                    root.picking = !root.picking;
                }
            }
        }

        // Which colour is which calendar
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            spacing: 12

            Repeater {
                model: root.legend

                delegate: Row {
                    required property var modelData

                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 3
                        color: modelData.color
                    }
                    Label {
                        text: modelData.name
                        font.pixelSize: 10
                        color: Theme.subtext0
                    }
                }
            }
        }
        IconButton {
            visible: !root.showingToday || root.picking
            glyph: Theme.glyph(0xf00f6) // 󰃶
            text: "Today"
            onClicked: {
                root.picking = false;
                root.reset();
            }
        }
        IconButton {
            glyph: Theme.glyph(0xf0141) // 󰅁
            onClicked: root.picking ? root.pickerYear-- : root.shift(-1)
        }
        IconButton {
            glyph: Theme.glyph(0xf0142) // 󰅂
            onClicked: root.picking ? root.pickerYear++ : root.shift(1)
        }
    }

    // The days, or the month/year picker in the same space
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: grid.implicitHeight

    GridLayout {
        id: grid

        width: parent.width
        opacity: root.picking ? 0 : 1
        enabled: !root.picking
        columns: root.weekNumbers ? 8 : 7
        columnSpacing: 4
        rowSpacing: 4

        // Weekday names
        Item {
            visible: root.weekNumbers
            Layout.preferredWidth: 22
            Layout.preferredHeight: 18
        }
        Repeater {
            model: 7

            delegate: Label {
                required property int index
                readonly property int weekday: (root.weekStart + index) % 7

                Layout.fillWidth: true
                Layout.preferredHeight: 18
                horizontalAlignment: Text.AlignHCenter
                text: root.dayNames[weekday]
                font.pixelSize: 10
                font.bold: true
                color: weekday === 0 || weekday === 6 ? Theme.overlay1 : Theme.subtext0
            }
        }

        Repeater {
            model: 6 * 8

            delegate: Loader {
                id: slot

                required property int index
                readonly property int row: Math.floor(index / 8)
                readonly property int column: index % 8 // 0: week number

                visible: column > 0 || root.weekNumbers
                Layout.fillWidth: column > 0
                Layout.preferredWidth: column === 0 ? 22 : 104
                Layout.preferredHeight: 92
                sourceComponent: column === 0 ? weekNumber : dayBox
            }
        }
    }

    // Month/year picker: a year with ‹ › (or scroll) and its twelve months
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        visible: root.picking
        spacing: 16

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            IconButton {
                glyph: Theme.glyph(0xf0141) // 󰅁
                onClicked: root.pickerYear--
            }
            Label {
                text: root.pickerYear
                font.pixelSize: 26
                font.bold: true
                color: root.pickerYear === root.today.getFullYear() ? Theme.lavender : Theme.text
            }
            IconButton {
                glyph: Theme.glyph(0xf0142) // 󰅂
                onClicked: root.pickerYear++
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 4
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: 12

                delegate: Rectangle {
                    id: monthButton

                    required property int index
                    readonly property bool viewing: root.pickerYear === root.year && index === root.month
                    readonly property bool current: root.pickerYear === root.today.getFullYear() && index === root.today.getMonth()

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: viewing ? Theme.lavender : monthMouse.containsMouse ? Theme.surface1 : Theme.alpha(Theme.surface0, 0.6)
                    border.width: current && !viewing ? 1 : 0
                    border.color: Theme.lavender

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Label {
                        anchors.centerIn: parent
                        text: Qt.locale().standaloneMonthName(monthButton.index, Locale.LongFormat)
                        font.pixelSize: 14
                        font.bold: monthButton.viewing || monthButton.current
                        color: monthButton.viewing ? Theme.crust : monthButton.current ? Theme.lavender : Theme.text
                    }
                    MouseArea {
                        id: monthMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.picking = false;
                            root.jump(root.pickerYear, monthButton.index);
                        }
                    }
                }
            }
        }
    }
    }

    Component {
        id: weekNumber

        Label {
            readonly property int row: parent?.row ?? 0

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            topPadding: 6
            text: root.isoWeek(root.addDays(root.first, row * 7))
            font.pixelSize: 10
            color: Theme.overlay0
        }
    }

    Component {
        id: dayBox

        Rectangle {
            id: cell

            readonly property int row: parent?.row ?? 0
            readonly property int column: parent?.column ?? 1
            readonly property date day: root.addDays(root.first, row * 7 + column - 1)
            readonly property string key: Qt.formatDate(day, "yyyy-MM-dd")
            readonly property bool inMonth: day.getMonth() === root.month
            readonly property bool isToday: root.sameDay(day, root.today)
            readonly property bool isSelected: root.sameDay(day, root.selected)
            readonly property var items: root.events[key] ?? []
            readonly property var weather: root.forecast[key] ?? null
            readonly property int shown: items.length > 3 ? 2 : items.length

            radius: 8
            color: isSelected ? Theme.alpha(Theme.lavender, 0.12) : mouse.containsMouse ? Theme.alpha(Theme.surface0, 0.8) : Theme.alpha(Theme.surface0, inMonth ? 0.4 : 0.15)
            border.width: isSelected ? 1 : 0
            border.color: Theme.alpha(Theme.lavender, 0.7)

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(cell.day)
                onDoubleClicked: root.activated(cell.day)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 2

                // Day number and forecast
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Rectangle {
                        Layout.preferredWidth: Math.max(22, dayNumber.implicitWidth + 10)
                        Layout.preferredHeight: 20
                        radius: 6
                        color: cell.isToday ? Theme.lavender : "transparent"

                        Label {
                            id: dayNumber
                            anchors.centerIn: parent
                            text: cell.day.getDate()
                            font.bold: cell.isToday || cell.isSelected
                            color: cell.isToday ? Theme.crust : !cell.inMonth ? Theme.surface2 : cell.isSelected ? Theme.lavender : Theme.text
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Label {
                        visible: !!cell.weather
                        readonly property var info: cell.weather ? Weather.describe(cell.weather.code, false) : null

                        text: info ? `${Theme.glyph(info[0])} ${cell.weather.max}°` : ""
                        font.pixelSize: 10
                        color: info ? info[2] : Theme.text
                        opacity: cell.inMonth ? 1 : 0.5
                    }
                }

                // Appointments
                Repeater {
                    model: cell.items.slice(0, cell.shown)

                    delegate: Rectangle {
                        id: chip

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 16
                        radius: 4
                        // All day: solid in the calendar's colour; timed: tinted with a bar
                        color: modelData.allDay ? modelData.colour : Theme.alpha(modelData.colour, 0.3)
                        opacity: cell.inMonth ? 1 : 0.5
                        clip: true

                        Rectangle {
                            visible: !chip.modelData.allDay
                            width: 3
                            height: parent.height
                            color: chip.modelData.colour
                        }
                        Label {
                            anchors.fill: parent
                            anchors.leftMargin: chip.modelData.allDay ? 5 : 6
                            anchors.rightMargin: 3
                            text: chip.modelData.allDay ? chip.modelData.title : `${Qt.formatTime(chip.modelData.start, "HH:mm")} ${chip.modelData.title}`
                            font.pixelSize: 10
                            color: chip.modelData.allDay ? Theme.readableOn(chip.modelData.colour) : Theme.text
                        }
                    }
                }
                Label {
                    visible: cell.items.length > cell.shown
                    text: `+${cell.items.length - cell.shown} more`
                    font.pixelSize: 9
                    color: Theme.overlay1
                    leftPadding: 4
                }
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }

    WheelHandler {
        target: null
        onWheel: event => {
            const step = event.angleDelta.y > 0 ? -1 : 1;
            if (root.picking)
                root.pickerYear += step;
            else
                root.shift(step);
        }
    }
}
