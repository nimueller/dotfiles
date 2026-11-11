pragma Singleton

import QtQuick
import Quickshell

// WMO present weather codes (table 4677, as weather.py gives them) as glyph,
// description and colour, and the wind direction as a compass point.
Singleton {
    readonly property var compassPoints: [I18n.tr("N"), I18n.tr("NE"), I18n.tr("E"), I18n.tr("SE"), I18n.tr("S"), I18n.tr("SW"), I18n.tr("W"), I18n.tr("NW")]

    // -> [glyph code point, description, colour]
    function describe(code, night) {
        if (code === 0) {
            return night ? [0xf0594, I18n.tr("Clear sky"), Theme.lavender] : [0xf0599, I18n.tr("Clear sky"), Theme.yellow];
        }
        if (code <= 2) {
            const name = code === 1 ? I18n.tr("Mostly clear") : I18n.tr("Partly cloudy");
            return night ? [0xf0f31, name, Theme.lavender] : [0xf0595, name, Theme.yellow];
        }
        if (code === 3) {
            return [0xf0590, I18n.tr("Overcast"), Theme.overlay2];
        }
        if (code <= 49) {
            return [0xf0591, I18n.tr("Fog"), Theme.overlay1];
        }
        if (code <= 57) {
            return [0xf0597, code >= 56 ? I18n.tr("Freezing drizzle") : I18n.tr("Drizzle"), Theme.sapphire];
        }
        if (code <= 67) {
            let rain = I18n.tr("Rain");
            if (code >= 66) {
                rain = I18n.tr("Freezing rain");
            } else if (code === 65) {
                rain = I18n.tr("Heavy rain");
            }
            return [0xf0597, rain, Theme.blue];
        }
        if (code <= 69) {
            return [0xf067f, I18n.tr("Sleet"), Theme.sapphire];
        }
        if (code <= 79) {
            return [0xf0598, code === 77 ? I18n.tr("Snow grains") : I18n.tr("Snow"), Theme.text];
        }
        if (code <= 82) {
            return [0xf0596, I18n.tr("Rain showers"), Theme.blue];
        }
        if (code <= 84) {
            return [0xf067f, I18n.tr("Sleet showers"), Theme.sapphire];
        }
        if (code <= 86) {
            return [0xf0598, I18n.tr("Snow showers"), Theme.text];
        }
        return [0xf067e, code >= 96 ? I18n.tr("Thunderstorm, hail") : I18n.tr("Thunderstorm"), Theme.peach];
    }

    // Degrees (where the wind comes from) -> "SW"
    function compass(degrees) {
        const index = Math.round(degrees / 45) % compassPoints.length;
        return compassPoints[index];
    }
}
