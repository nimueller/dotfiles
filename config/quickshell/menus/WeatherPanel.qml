import QtQuick
import QtQuick.Layouts

// Current weather: the METAR of the nearest airport (aviationweather.gov:
// temperature, dew point, wind, visibility, QNH, clouds) when there is one,
// otherwise Open-Meteo's current values. The days ahead are in the grid.
ColumnLayout {
    id: root

    property var weather: null // Open-Meteo /v1/forecast JSON
    property var metar: null // aviationweather.gov METAR JSON, with .distance (km)
    property string place: ""
    property string error: ""

    signal configure

    readonly property var current: weather?.current ?? null
    readonly property bool night: current ? current.is_day === 0 : false
    readonly property var today: Weather.daily(weather)[weather?.daily?.time?.[0]] ?? null
    readonly property var now: metar ? Weather.describe(Weather.metarCode(metar), night) : current ? Weather.describe(current.weather_code, night) : null
    readonly property real temp: metar ? metar.temp : current?.temperature_2m ?? 0
    readonly property bool cavok: (metar?.rawOb ?? "").includes("CAVOK")

    function wind(m) {
        if (!m.wspd)
            return "Calm";
        const dir = m.wdir === "VRB" ? "Variable" : `${String(m.wdir).padStart(3, "0")}°`;
        const gust = m.wgst ? ` G${m.wgst}` : "";
        return `${dir} ${m.wspd}${gust} kt (${Math.round(m.wspd * 1.852)} km/h)`;
    }

    function clouds(m) {
        if (cavok)
            return "CAVOK";
        const layers = (m.clouds ?? []).filter(c => c.cover && c.base !== null && c.base !== undefined).map(c => `${c.cover} ${c.base} ft`);
        return layers.length ? layers.join(", ") : (m.clouds ?? []).map(c => c.cover).join(" ") || "No clouds";
    }

    function age(epoch) {
        const minutes = Math.round((Date.now() / 1000 - epoch) / 60);
        return minutes < 60 ? `${minutes} min ago` : `${Math.floor(minutes / 60)} h ${minutes % 60} min ago`;
    }

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        visible: !!(root.metar || root.current)
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
                text: root.metar ? `Dew point ${root.metar.dewp}°  ·  ${Weather.humidity(root.metar.temp, root.metar.dewp)}% humidity` : root.now ? root.now[1] : ""
                color: Theme.subtext0
            }
        }
    }

    // Aviation report
    Repeater {
        model: root.metar ? [
            [0xf059d, root.wind(root.metar)],
            [0xf0208, `Visibility ${root.cavok ? "≥ 10 km" : Weather.visibility(root.metar.visib)}`],
            [0xf029a, `QNH ${root.metar.altim ? Math.round(root.metar.altim) : "–"} hPa`],
            [0xf015f, root.clouds(root.metar)]
        ].concat(root.metar.wxString ? [[0xf0597, `Weather ${root.metar.wxString}`]] : []) : []

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

    // Station, age, flight category
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: !!root.metar
        spacing: 6

        Label {
            Layout.fillWidth: true
            text: root.metar ? `${root.metar.icaoId} · ${root.metar.name?.split(",")[0] ?? ""} · ${Math.round(root.metar.distance)} km · ${root.age(root.metar.obsTime)}` : ""
            font.pixelSize: 10
            color: Theme.overlay1
        }
        Rectangle {
            visible: !!root.metar?.fltCat
            implicitWidth: cat.implicitWidth + 10
            implicitHeight: 16
            radius: 8
            color: Theme.alpha(Weather.flightColour(root.metar?.fltCat), 0.2)

            Label {
                id: cat
                anchors.centerIn: parent
                text: root.metar?.fltCat ?? ""
                font.pixelSize: 9
                font.bold: true
                color: Weather.flightColour(root.metar?.fltCat)
            }
        }
    }
    Label {
        Layout.fillWidth: true
        visible: !!root.metar
        text: root.metar?.rawOb ?? ""
        font.pixelSize: 9
        color: Theme.overlay0
        wrapMode: Text.WrapAnywhere
        elide: Text.ElideNone
    }

    // Open-Meteo fallback line
    Label {
        Layout.fillWidth: true
        visible: !root.metar && !!root.current
        text: root.current ? [root.place, `feels ${Math.round(root.current.apparent_temperature)}°`, `${Math.round(root.current.wind_speed_10m)} km/h`, root.today?.rain ? `${Theme.glyph(0xf058c)} ${root.today.rain}%` : ""].filter(x => x).join("  ·  ") : ""
        font.pixelSize: 10
        color: Theme.overlay1
    }

    // No data (yet)
    RowLayout {
        Layout.fillWidth: true
        visible: !root.metar && !root.current
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: root.error || "Loading weather…"
            color: root.error ? Theme.red : Theme.overlay0
            wrapMode: Text.Wrap
        }
        IconButton {
            visible: !!root.error
            glyph: Theme.glyph(0xf034e) // 󰍎
            text: "Location"
            onClicked: root.configure()
        }
    }
}
