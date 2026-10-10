import QtQuick
import QtQuick.Layouts

// Hour-by-hour forecast of one day from Open-Meteo's hourly arrays, as a
// strip to scroll sideways. Starts at the current hour today, at 7 otherwise.
ListView {
    id: root

    property var weather: null // Open-Meteo /v1/forecast JSON with `hourly`
    required property date day

    readonly property var hours: {
        const h = weather?.hourly;
        if (!h)
            return [];
        const key = Qt.formatDate(day, "yyyy-MM-dd");
        const out = [];
        h.time.forEach((t, i) => {
            if (t.startsWith(key) && h.temperature_2m[i] !== null)
                out.push({
                    hour: parseInt(t.slice(11, 13)),
                    code: h.weather_code[i],
                    temp: Math.round(h.temperature_2m[i]),
                    rain: h.precipitation_probability?.[i] ?? 0,
                    night: h.is_day?.[i] === 0
                });
        });
        return out;
    }

    function scrollToStart() {
        const now = new Date();
        const today = Qt.formatDate(now, "yyyy-MM-dd") === Qt.formatDate(day, "yyyy-MM-dd");
        positionViewAtIndex(Math.max(0, hours.findIndex(h => h.hour >= (today ? now.getHours() : 7))), ListView.Beginning);
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
        readonly property bool isNow: modelData.hour === new Date().getHours() && Qt.formatDate(root.day, "yyyy-MM-dd") === Qt.formatDate(new Date(), "yyyy-MM-dd")

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

    WheelHandler {
        // Vertical wheel scrolls the strip sideways
        onWheel: event => root.flick(event.angleDelta.y * 6, 0)
    }
}
