import QtQuick
import QtQuick.Layouts

// New or edited appointment: title, place, date(s), times or all day,
// reminders, and for new ones the (writable) calendar to save it in. Dates as yyyy-mm-dd or
// dd.mm.yyyy. Picking another day in the grid moves it there.
ColumnLayout {
    id: root

    required property date day
    property var calendars: [] // writable: [{ href, name, color }]
    property bool busy: false
    property string error: ""

    property var target: null // the event being edited, null for a new one
    property string calendar: ""
    property bool allDay: false
    property var alarms: [] // minutes before the start
    property string problem: ""

    signal saveRequested(var event)
    signal cancelled

    // Fresh form for `day`
    function reset() {
        target = null;
        title.text = "";
        place.text = "";
        startDate.text = Qt.formatDate(day, "yyyy-MM-dd");
        endDate.text = startDate.text;
        startTime.text = "09:00";
        endTime.text = "10:00";
        allDay = false;
        alarms = [15];
        problem = "";
        if (!calendars.some(c => c.href === calendar))
            calendar = calendars[0]?.href ?? "";
        title.focusField();
    }

    // Form filled with an existing event (all-day end shown inclusive)
    function edit(event) {
        target = event;
        title.text = event.title;
        place.text = event.location ?? "";
        allDay = event.allDay;
        const last = event.allDay ? new Date(event.end.getFullYear(), event.end.getMonth(), event.end.getDate() - 1) : event.end;
        startDate.text = Qt.formatDate(event.start, "yyyy-MM-dd");
        endDate.text = Qt.formatDate(last < event.start ? event.start : last, "yyyy-MM-dd");
        startTime.text = event.allDay ? "09:00" : Qt.formatTime(event.start, "HH:mm");
        endTime.text = event.allDay ? "10:00" : Qt.formatTime(event.end, "HH:mm");
        calendar = event.calendar;
        alarms = (event.alarms ?? []).slice();
        problem = "";
        title.focusField();
    }

    function parseDate(text) {
        let m = text.trim().match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
        if (m)
            return new Date(+m[1], +m[2] - 1, +m[3]);
        m = text.trim().match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/);
        return m ? new Date(+m[3], +m[2] - 1, +m[1]) : null;
    }

    function parseTime(text) {
        const m = text.trim().match(/^(\d{1,2})(?::(\d{2}))?$/);
        return m && +m[1] < 24 && +(m[2] ?? 0) < 60 ? [+m[1], +(m[2] ?? 0)] : null;
    }

    function submit() {
        const from = parseDate(startDate.text), to = parseDate(endDate.text || startDate.text);
        const t1 = parseTime(startTime.text), t2 = parseTime(endTime.text);
        if (!title.text.trim())
            problem = "Give it a title";
        else if (!from || !to)
            problem = "Dates as 2026-10-11 or 11.10.2026";
        else if (!allDay && (!t1 || !t2))
            problem = "Times as 9:00 or 14:30";
        else if (!calendar)
            problem = "No writable Nextcloud calendar";
        else {
            const start = new Date(from.getFullYear(), from.getMonth(), from.getDate(), allDay ? 0 : t1[0], allDay ? 0 : t1[1]);
            const end = new Date(to.getFullYear(), to.getMonth(), to.getDate(), allDay ? 0 : t2[0], allDay ? 0 : t2[1]);
            if (end < start) {
                problem = "It ends before it starts";
                return;
            }
            problem = "";
            const fmt = allDay ? "yyyy-MM-dd" : "yyyy-MM-ddTHH:mm";
            root.saveRequested({
                calendar,
                href: target?.href ?? "",
                etag: target?.etag ?? "",
                title: title.text.trim(),
                location: place.text.trim(),
                allDay,
                start: Qt.formatDateTime(start, fmt),
                end: Qt.formatDateTime(end, fmt),
                alarms
            });
        }
    }

    onDayChanged: {
        // Picking another day in the grid moves the appointment there,
        // keeping how many days it spans
        const from = parseDate(startDate.text), to = parseDate(endDate.text);
        const span = from && to ? Math.round((to - from) / 86400000) : 0;
        startDate.text = Qt.formatDate(day, "yyyy-MM-dd");
        endDate.text = Qt.formatDate(new Date(day.getFullYear(), day.getMonth(), day.getDate() + Math.max(span, 0)), "yyyy-MM-dd");
    }

    spacing: 6

    SectionTitle {
        text: root.target ? "Edit appointment" : "New appointment"
    }

    InputField {
        id: title
        Layout.fillWidth: true
        placeholder: "Title"
        accent: Theme.mauve
        onAccepted: root.submit()
    }
    InputField {
        id: place
        Layout.fillWidth: true
        placeholder: "Place (optional)"
        accent: Theme.mauve
        onAccepted: root.submit()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: "All day"
            color: Theme.subtext1
        }
        Switch {
            checked: root.allDay
            accent: Theme.mauve
            onToggled: root.allDay = !root.allDay
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: root.allDay ? 2 : 3
        columnSpacing: 6
        rowSpacing: 6

        Label {
            text: "From"
            color: Theme.overlay1
            font.pixelSize: 11
        }
        InputField {
            id: startDate
            Layout.fillWidth: true
            placeholder: "yyyy-mm-dd"
            accent: Theme.mauve
            onAccepted: root.submit()
        }
        InputField {
            id: startTime
            visible: !root.allDay
            Layout.preferredWidth: 64
            placeholder: "hh:mm"
            accent: Theme.mauve
            onAccepted: root.submit()
        }
        Label {
            text: "To"
            color: Theme.overlay1
            font.pixelSize: 11
        }
        InputField {
            id: endDate
            Layout.fillWidth: true
            placeholder: "yyyy-mm-dd"
            accent: Theme.mauve
            onAccepted: root.submit()
        }
        InputField {
            id: endTime
            visible: !root.allDay
            Layout.preferredWidth: 64
            placeholder: "hh:mm"
            accent: Theme.mauve
            onAccepted: root.submit()
        }
    }

    function toggleAlarm(m) {
        alarms = alarms.includes(m) ? alarms.filter(x => x !== m) : [...alarms, m].sort((a, b) => a - b);
    }

    // Reminders: presets, plus any other value typed in
    Label {
        text: allDay ? "Reminders (before midnight at the start)" : "Reminders"
        font.pixelSize: 11
        color: Theme.overlay1
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: [...new Set([...Reminders.presets, ...root.alarms])].sort((a, b) => a - b)

            delegate: Rectangle {
                id: reminder

                required property int modelData
                readonly property bool on: root.alarms.includes(modelData)

                width: reminderLabel.implicitWidth + 16
                height: 22
                radius: 11
                color: on ? Theme.alpha(Theme.mauve, 0.25) : reminderMouse.containsMouse ? Theme.surface1 : Theme.surface0
                border.width: on ? 1 : 0
                border.color: Theme.mauve

                Label {
                    id: reminderLabel
                    anchors.centerIn: parent
                    text: Reminders.describe(reminder.modelData)
                    font.pixelSize: 10
                    color: reminder.on ? Theme.mauve : Theme.subtext0
                }
                MouseArea {
                    id: reminderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleAlarm(reminder.modelData)
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        InputField {
            id: customAlarm
            Layout.fillWidth: true
            placeholder: "Other: 45m, 2h, 3d …"
            accent: Theme.mauve
            onAccepted: addAlarm.clicked()
        }
        IconButton {
            id: addAlarm
            glyph: Theme.glyph(0xf0415) // 󰐕
            text: "Add"
            onClicked: {
                const m = Reminders.parse(customAlarm.text);
                if (m === null) {
                    root.problem = "Reminders like 45m, 2h or 3d";
                    return;
                }
                root.problem = "";
                if (!root.alarms.includes(m))
                    root.toggleAlarm(m);
                customAlarm.text = "";
            }
        }
    }

    // Calendar to save into (an edited event stays in its calendar)
    Flow {
        Layout.fillWidth: true
        visible: !root.target
        spacing: 6

        Repeater {
            model: root.calendars

            delegate: Rectangle {
                id: choice

                required property var modelData
                readonly property bool chosen: root.calendar === modelData.href

                width: choiceRow.implicitWidth + 16
                height: 24
                radius: 12
                color: chosen ? Theme.alpha(modelData.color, 0.25) : choiceMouse.containsMouse ? Theme.surface1 : Theme.surface0
                border.width: chosen ? 1 : 0
                border.color: modelData.color

                Row {
                    id: choiceRow
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: choice.modelData.color
                    }
                    Label {
                        text: choice.modelData.name
                        font.pixelSize: 11
                        color: choice.chosen ? Theme.text : Theme.subtext0
                    }
                }
                MouseArea {
                    id: choiceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.calendar = choice.modelData.href
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !!(root.problem || root.error)
        text: root.problem || root.error
        font.pixelSize: 10
        color: Theme.red
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Item {
            Layout.fillWidth: true
        }
        IconButton {
            text: "Cancel"
            onClicked: root.cancelled()
        }
        IconButton {
            glyph: Theme.glyph(0xf012c) // 󰄬
            text: root.busy ? "Saving…" : "Save"
            accent: Theme.mauve
            active: true
            onClicked: if (!root.busy) root.submit()
        }
    }
}
