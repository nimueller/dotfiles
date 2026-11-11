import QtQuick
import QtQuick.Layouts

// Hour-by-hour forecast of one day from weather.py's hourly list, as a strip
// to scroll sideways. Starts at the current hour today, at 7 otherwise.
ListView {
    id: root

    property var hourly: [] // weather.py's: [{ time, temp, code, rain, night }]
    required property date day

    readonly property var hours: {
        const key = Qt.formatDate(day, "yyyy-MM-dd");
        const out = [];
        for (const h of hourly) {
            if (!h.time.startsWith(key)) {
                continue;
            }
            out.push({
                hour: parseInt(h.time.slice(11, 13)),
                code: h.code,
                temp: h.temp,
                rain: h.rain ?? 0,
                night: h.night
            });
        }
        return out;
    }

    function scrollToStart() {
        const now = new Date();
        const today = Qt.formatDate(now, "yyyy-MM-dd") === Qt.formatDate(day, "yyyy-MM-dd");
        const firstHour = today ? now.getHours() : 7;
        const index = hours.findIndex(h => h.hour >= firstHour);
        positionViewAtIndex(Math.max(0, index), ListView.Beginning);
    }

    onHoursChanged: Qt.callLater(scrollToStart)

    visible: hours.length > 0
    implicitHeight: 70
    orientation: ListView.Horizontal
    spacing: 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: hours

    delegate: Rectangle {
        id: cell

        required property var modelData
        readonly property var info: Weather.describe(modelData.code, modelData.night)
        readonly property bool isNow: {
            const now = new Date();
            if (modelData.hour !== now.getHours()) {
                return false;
            }
            return Qt.formatDate(root.day, "yyyy-MM-dd") === Qt.formatDate(now, "yyyy-MM-dd");
        }

        width: 42
        height: root.height
        radius: 8
        color: isNow ? Theme.alpha(Theme.lavender, 0.14) : "transparent"

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: String(cell.modelData.hour).padStart(2, "0")
                font.pixelSize: 10
                color: cell.isNow ? Theme.lavender : Theme.overlay1
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: Theme.glyph(cell.info[0])
                font.pixelSize: 15
                color: cell.info[2]
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: `${cell.modelData.temp}°`
                font.pixelSize: 11
                font.bold: true
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: cell.modelData.rain >= 10 ? `${cell.modelData.rain}%` : " "
                font.pixelSize: 9
                color: Theme.sapphire
            }
        }
    }

    // Vertical wheel scrolls the strip sideways. A MouseArea that takes no
    // buttons, on the list itself rather than its moving content: a
    // WheelHandler got no wheel events from a real mouse in the Quickshell
    // window.
    MouseArea {
        parent: root
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: event => root.flick(event.angleDelta.y * 6, 0)
    }
}
