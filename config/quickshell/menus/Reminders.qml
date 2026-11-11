pragma Singleton

import QtQuick
import Quickshell

// Event reminders as minutes before the start: presets, wording, parsing.
Singleton {
    readonly property var presets: [0, 5, 15, 30, 60, 1440]

    // 15 -> "15 min", 60 -> "1 h", 1440 -> "1 day", 0 -> I18n.tr("At start")
    function describe(m) {
        if (m === 0) {
            return I18n.tr("At start");
        }
        const n = Math.abs(m);
        let amount = I18n.tr("%1 min", n);
        if (n % 1440 === 0) {
            amount = I18n.tr(n === 1440 ? "%1 day" : "%1 days", n / 1440);
        } else if (n % 60 === 0) {
            amount = I18n.tr("%1 h", n / 60);
        }
        return m < 0 ? I18n.tr("%1 after", amount) : amount;
    }

    // "45m", "2h", "3d", "1w" or plain minutes -> minutes, or null
    function parse(text) {
        const m = text.trim().toLowerCase().match(/^(\d+)\s*(m|min|h|d|w)?$/);
        if (!m) {
            return null;
        }
        return parseInt(m[1]) * ({
                h: 60,
                d: 1440,
                w: 10080
            }[m[2]] ?? 1);
    }
}
