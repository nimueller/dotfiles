import QtQuick
import QtQuick.Layouts

// Current weather from an Open-Meteo response, plus today's range. The
// days ahead are shown in the month grid.
ColumnLayout {
    id: root

    property var weather: null // Open-Meteo /v1/forecast JSON
    property string place: ""
    property string error: ""

    signal configure

    readonly property var current: weather?.current ?? null
    readonly property var now: current ? Weather.describe(current.weather_code, current.is_day === 0) : null
    readonly property var today: Weather.daily(weather)[weather?.daily?.time?.[0]] ?? null

    spacing: 4

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

            RowLayout {
                spacing: 8

                Label {
                    text: root.current ? `${Math.round(root.current.temperature_2m)}°` : ""
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
                text: root.now ? root.now[1] : ""
                color: Theme.subtext0
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !!root.current
        text: root.current ? [root.place, `feels ${Math.round(root.current.apparent_temperature)}°`, `${Math.round(root.current.wind_speed_10m)} km/h`, root.today?.rain ? `${Theme.glyph(0xf058c)} ${root.today.rain}%` : ""].filter(x => x).join("  ·  ") : ""
        font.pixelSize: 10
        color: Theme.overlay1
    }

    // No data (yet)
    RowLayout {
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
            text: "Location"
            onClicked: root.configure()
        }
    }
}
