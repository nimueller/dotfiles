pragma Singleton

import QtQuick
import Quickshell

// WMO weather codes (Open-Meteo) as glyph, description and colour.
Singleton {
    // -> [glyph code point, description, colour]
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

    // Open-Meteo daily arrays -> { "yyyy-MM-dd": { code, max, min, rain } }
    function daily(weather) {
        const d = weather?.daily;
        const out = {};
        if (!d)
            return out;
        d.time.forEach((t, i) => {
            // The last forecast days can come without values
            if (d.weather_code[i] === null || d.temperature_2m_max[i] === null)
                return;
            out[t] = {
                code: d.weather_code[i],
                max: Math.round(d.temperature_2m_max[i]),
                min: Math.round(d.temperature_2m_min[i] ?? d.temperature_2m_max[i]),
                rain: d.precipitation_probability_max?.[i] ?? null
            };
        });
        return out;
    }
}
