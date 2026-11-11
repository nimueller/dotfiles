import QtQuick
import QtQuick.Layouts

// Current weather: the newest report of the nearest weather station
// (temperature, humidity, wind, dew point, visibility, pressure, clouds)
// when there is one close by, otherwise the forecast for this hour. All from
// the Deutscher Wetterdienst via weather.py; the days ahead are in the grid.
ColumnLayout {
    id: root

    property var weather: null // weather.py's JSON
    property string place: ""
    property string error: ""

    signal configure

    readonly property var current: weather?.current ?? null
    readonly property var today: weather?.daily?.[Qt.formatDate(new Date(), "yyyy-MM-dd")] ?? null
    // The forecast's hour that ends next (its values are for the hour before)
    readonly property var thisHour: {
        const now = Qt.formatDateTime(new Date(), "yyyy-MM-ddTHH:mm");
        return (weather?.hourly ?? []).find(h => h.time >= now) ?? null;
    }
    readonly property var now: {
        if (current && current.code !== null) {
            return Weather.describe(current.code, current.night);
        }
        if (thisHour) {
            return Weather.describe(thisHour.code, thisHour.night);
        }
        return null;
    }
    readonly property real temp: current ? current.temp : thisHour?.temp ?? 0

    // The station's report as rows: [glyph, text], only what it reported
    function reportRows() {
        const report = root.current;
        if (!report) {
            return [];
        }
        const rows = [];
        if (report.windSpeed !== null) {
            rows.push([0xf059d, root.wind(report)]);
        }
        if (report.dewPoint !== null) {
            rows.push([0xf058c, I18n.tr("Dew point %1°", report.dewPoint.toFixed(1))]);
        }
        if (report.visibility !== null) {
            rows.push([0xf0208, I18n.tr("Visibility %1", root.visibility(report.visibility))]);
        }
        if (report.pressure !== null) {
            rows.push([0xf029a, I18n.tr("Pressure %1 hPa", Math.round(report.pressure))]);
        }
        if (report.cloudCover !== null) {
            rows.push([0xf015f, root.clouds(report)]);
        }
        if (report.rain) {
            rows.push([0xf0597, I18n.tr("%1 mm in the last hour", report.rain.toFixed(1))]);
        }
        return rows;
    }

    function wind(report) {
        if (report.windSpeed === 0) {
            return I18n.tr("Calm");
        }
        const from = report.windDirection === null ? "" : `${Weather.compass(report.windDirection)} `;
        const gusts = report.gusts ? I18n.tr(", gusts %1 km/h", Math.round(report.gusts)) : "";
        return `${from}${Math.round(report.windSpeed)} km/h${gusts}`;
    }

    function visibility(km) {
        if (km >= 10) {
            return `${Math.round(km)} km`;
        }
        return km < 1 ? `${Math.round(km * 1000)} m` : `${km.toFixed(1)} km`;
    }

    function clouds(report) {
        const base = report.cloudBase === null ? "" : I18n.tr(", base %1 m", Math.round(report.cloudBase));
        return I18n.tr("Clouds %1%%2", Math.round(report.cloudCover), base);
    }

    function age(epoch) {
        const minutes = Math.round((Date.now() / 1000 - epoch) / 60);
        return minutes < 60 ? I18n.tr("%1 min ago", minutes) : I18n.tr("%1 h %2 min ago", Math.floor(minutes / 60), minutes % 60);
    }

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        visible: !!root.now
        spacing: 12

        Label {
            text: root.now ? Theme.glyph(root.now[0]) : ""
            font.pixelSize: 40
            color: root.now ? root.now[2] : Theme.text
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                spacing: 8

                Label {
                    text: `${Math.round(root.temp)}°`
                    font.pixelSize: 26
                    font.bold: true
                }
                Label {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 5
                    visible: !!root.today
                    text: root.today ? `${root.today.max}° / ${root.today.min}°` : ""
                    color: Theme.overlay1
                }
            }
            Label {
                Layout.fillWidth: true
                text: {
                    if (!root.now) {
                        return "";
                    }
                    const humidity = root.current?.humidity ?? null;
                    if (humidity === null) {
                        return root.now[1];
                    }
                    return I18n.tr("%1  ·  %2% humidity", root.now[1], Math.round(humidity));
                }
                color: Theme.subtext0
            }
        }
    }

    // Station report
    Repeater {
        model: root.reportRows()

        delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.preferredWidth: 14
                text: Theme.glyph(modelData[0])
                font.pixelSize: 11
                color: Theme.overlay2
            }
            Label {
                Layout.fillWidth: true
                text: modelData[1]
                font.pixelSize: 11
                color: Theme.subtext1
            }
        }
    }

    // Station, distance, age
    Label {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: !!root.current
        text: {
            const report = root.current;
            if (!report) {
                return "";
            }
            const distance = `${Math.round(report.station.distance)} km`;
            return `DWD · ${report.station.name} · ${distance} · ${root.age(report.time)}`;
        }
        font.pixelSize: 10
        color: Theme.overlay1
    }

    // Forecast only: no station reported close by
    Label {
        Layout.fillWidth: true
        visible: !root.current && !!root.thisHour
        text: {
            const hour = root.thisHour;
            if (!hour) {
                return "";
            }
            const rain = hour.rain ? `${Theme.glyph(0xf058c)} ${hour.rain}%` : "";
            return [root.place, I18n.tr("DWD forecast"), rain].filter(x => x).join("  ·  ");
        }
        font.pixelSize: 10
        color: Theme.overlay1
    }

    // No data (yet)
    RowLayout {
        Layout.fillWidth: true
        visible: !root.now
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: root.error || I18n.tr("Loading weather…")
            color: root.error ? Theme.red : Theme.overlay0
            wrapMode: Text.Wrap
        }
        IconButton {
            visible: !!root.error
            glyph: Theme.glyph(0xf034e) // 󰍎
            text: I18n.tr("Location")
            onClicked: root.configure()
        }
    }
}
