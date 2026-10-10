pragma Singleton

import QtQuick
import Quickshell

// WMO weather codes (Open-Meteo) as glyph, description and colour, plus
// helpers for METAR reports (aviationweather.gov).
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

    // METAR (aviationweather.gov JSON) -> the closest WMO code, for the glyph
    function metarCode(m) {
        const wx = m.wxString ?? "";
        if (/TS/.test(wx))
            return 95;
        if (/SN|SG|PL|GS|GR/.test(wx))
            return /SH/.test(wx) ? 85 : 73;
        if (/RA|DZ|UP/.test(wx)) {
            if (/SH/.test(wx))
                return 80;
            if (/DZ/.test(wx))
                return 53;
            return wx.includes("+") ? 65 : wx.includes("-") ? 61 : 63;
        }
        if (/FG|BR|HZ|FU/.test(wx))
            return 45;
        const covers = (m.clouds ?? []).map(c => c.cover);
        if (covers.includes("OVC") || covers.includes("VV"))
            return 3;
        if (covers.includes("BKN"))
            return 3;
        if (covers.includes("SCT"))
            return 2;
        if (covers.includes("FEW"))
            return 1;
        return 0;
    }

    // Relative humidity (%) from temperature and dew point (Magnus formula)
    function humidity(t, td) {
        const f = x => Math.exp(17.625 * x / (243.04 + x));
        return Math.round(100 * f(td) / f(t));
    }

    function flightColour(category) {
        return ({ VFR: Theme.green, MVFR: Theme.blue, IFR: Theme.red, LIFR: Theme.mauve })[category] ?? Theme.overlay1;
    }

    // Visibility in statute miles ("6+" = 6 or more) as km
    function visibility(v) {
        if (v === undefined || v === null || v === "")
            return "";
        if (`${v}`.endsWith("+"))
            return "≥ 10 km";
        const km = parseFloat(v) * 1.609;
        return km >= 10 ? "≥ 10 km" : `${km < 5 ? km.toFixed(1) : Math.round(km)} km`;
    }

    function distanceKm(lat1, lon1, lat2, lon2) {
        const r = Math.PI / 180;
        const a = Math.sin((lat2 - lat1) * r / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin((lon2 - lon1) * r / 2) ** 2;
        return 6371 * 2 * Math.asin(Math.sqrt(a));
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
