import QtQuick
import QtQuick.Layouts

// Current weather and a 7-day forecast from an Open-Meteo response.
ColumnLayout {
    id: root

    property var weather: null // Open-Meteo /v1/forecast JSON
    property string place: ""
    property string error: ""

    signal configure

    // WMO weather code -> [glyph, description, colour]
    function describe(code, night) {
        if (code === 0)
            return night ? [0xf0594, "Clear", Theme.lavender] : [0xf0599, "Clear", Theme.yellow];
        if (code <= 2)
            return night ? [0xf0f31, code === 1 ? "Mostly clear" : "Partly cloudy", Theme.lavender] : [0xf0595, code === 1 ? "Mostly clear" : "Partly cloudy", Theme.yellow];
        if (code === 3)
            return [0xf0590, "Overcast", Theme.overlay2];
        if (code <= 48)
            return [0xf0591, "Fog", Theme.overlay1];
        if (code <= 57)
            return [0xf0597, code >= 56 ? "Freezing drizzle" : "Drizzle", Theme.sapphire];
        if (code <= 67)
            return [0xf0597, code >= 66 ? "Freezing rain" : code === 65 ? "Heavy rain" : "Rain", Theme.blue];
        if (code <= 77)
            return [0xf0598, code === 77 ? "Snow grains" : "Snow", Theme.text];
        if (code <= 82)
            return [0xf0596, "Rain showers", Theme.blue];
        if (code <= 86)
            return [0xf0598, "Snow showers", Theme.text];
        return [0xf067e, code >= 96 ? "Thunderstorm, hail" : "Thunderstorm", Theme.peach];
    }

    readonly property var current: weather?.current ?? null
    readonly property var now: current ? describe(current.weather_code, current.is_day === 0) : null
    readonly property var days: {
        const d = weather?.daily;
        if (!d)
            return [];
        return d.time.map((t, i) => ({
                    date: new Date(`${t}T12:00:00`),
                    code: d.weather_code[i],
                    max: Math.round(d.temperature_2m_max[i]),
                    min: Math.round(d.temperature_2m_min[i]),
                    rain: d.precipitation_probability_max?.[i] ?? null
                }));
    }

    spacing: 10

    // Now
    RowLayout {
        Layout.fillWidth: true
        visible: !!root.current
        spacing: 12

        Label {
            text: root.now ? Theme.glyph(root.now[0]) : ""
            font.pixelSize: 40
            color: root.now ? root.now[2] : Theme.text
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                text: root.current ? `${Math.round(root.current.temperature_2m)}°` : ""
                font.pixelSize: 26
                font.bold: true
            }
            Label {
                Layout.fillWidth: true
                text: root.now ? root.now[1] : ""
                color: Theme.subtext0
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !!root.current
        text: root.current ? `${root.place}  ·  feels ${Math.round(root.current.apparent_temperature)}°  ·  ${Math.round(root.current.wind_speed_10m)} km/h` : ""
        font.pixelSize: 10
        color: Theme.overlay1
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        visible: root.days.length > 0
        color: Theme.surface0
    }

    // Next days
    Repeater {
        model: root.days

        delegate: RowLayout {
            id: day

            required property var modelData
            required property int index
            readonly property var info: root.describe(modelData.code, false)

            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.preferredWidth: 40
                text: day.index === 0 ? "Today" : Qt.formatDate(day.modelData.date, "ddd")
                font.bold: day.index === 0
                color: day.index === 0 ? Theme.text : Theme.subtext0
            }
            Label {
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
                text: Theme.glyph(day.info[0])
                color: day.info[2]
            }
            Label {
                Layout.fillWidth: true
                text: day.modelData.rain ? `${Theme.glyph(0xf058c)} ${day.modelData.rain}%` : "" // 󰖌
                font.pixelSize: 10
                color: Theme.sapphire
                opacity: day.modelData.rain >= 30 ? 1 : 0.55
            }
            Label {
                text: `${day.modelData.max}°`
                font.bold: true
            }
            Label {
                Layout.preferredWidth: 28
                horizontalAlignment: Text.AlignRight
                text: `${day.modelData.min}°`
                color: Theme.overlay1
            }
        }
    }

    // No data (yet)
    ColumnLayout {
        Layout.fillWidth: true
        visible: !root.current
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
            text: "Set location"
            onClicked: root.configure()
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
