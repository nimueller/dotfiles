pragma Singleton

import QtQuick
import Quickshell

// WMO present weather codes (table 4677, as weather.py gives them) as glyph,
// description and colour, and the wind direction as a compass point.
Singleton {
    readonly property var compassPoints: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    // -> [glyph code point, description, colour]
    function describe(code, night) {
        if (code === 0) {
            return night ? [0xf0594, "Clear", Theme.lavender] : [0xf0599, "Clear", Theme.yellow];
        }
        if (code <= 2) {
            const name = code === 1 ? "Mostly clear" : "Partly cloudy";
            return night ? [0xf0f31, name, Theme.lavender] : [0xf0595, name, Theme.yellow];
        }
        if (code === 3) {
            return [0xf0590, "Overcast", Theme.overlay2];
        }
        if (code <= 49) {
            return [0xf0591, "Fog", Theme.overlay1];
        }
        if (code <= 57) {
            return [0xf0597, code >= 56 ? "Freezing drizzle" : "Drizzle", Theme.sapphire];
        }
        if (code <= 67) {
            let rain = "Rain";
            if (code >= 66) {
                rain = "Freezing rain";
            } else if (code === 65) {
                rain = "Heavy rain";
            }
            return [0xf0597, rain, Theme.blue];
        }
        if (code <= 69) {
            return [0xf067f, "Sleet", Theme.sapphire];
        }
        if (code <= 79) {
            return [0xf0598, code === 77 ? "Snow grains" : "Snow", Theme.text];
        }
        if (code <= 82) {
            return [0xf0596, "Rain showers", Theme.blue];
        }
        if (code <= 84) {
            return [0xf067f, "Sleet showers", Theme.sapphire];
        }
        if (code <= 86) {
            return [0xf0598, "Snow showers", Theme.text];
        }
        return [0xf067e, code >= 96 ? "Thunderstorm, hail" : "Thunderstorm", Theme.peach];
    }

    // Degrees (where the wind comes from) -> "SW"
    function compass(degrees) {
        const index = Math.round(degrees / 45) % compassPoints.length;
        return compassPoints[index];
    }
}
