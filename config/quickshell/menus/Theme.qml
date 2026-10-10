pragma Singleton

import QtQuick
import Quickshell

// Catppuccin Macchiato, same palette as waybar/macchiato.css.
Singleton {
    readonly property color rosewater: "#f4dbd6"
    readonly property color mauve: "#c6a0f6"
    readonly property color red: "#ed8796"
    readonly property color peach: "#f5a97f"
    readonly property color yellow: "#eed49f"
    readonly property color green: "#a6da95"
    readonly property color teal: "#8bd5ca"
    readonly property color sapphire: "#7dc4e4"
    readonly property color blue: "#8aadf4"
    readonly property color lavender: "#b7bdf8"
    readonly property color text: "#cad3f5"
    readonly property color subtext1: "#b8c0e0"
    readonly property color subtext0: "#a5adcb"
    readonly property color overlay2: "#939ab7"
    readonly property color overlay1: "#8087a2"
    readonly property color overlay0: "#6e738d"
    readonly property color surface2: "#5b6078"
    readonly property color surface1: "#494d64"
    readonly property color surface0: "#363a4f"
    readonly property color base: "#24273a"
    readonly property color mantle: "#1e2030"
    readonly property color crust: "#181926"

    readonly property string font: "CaskaydiaCove Nerd Font"

    // Colour `c` (a color or a "#rrggbb"/name string) with opacity `a`
    function alpha(c, a) {
        const col = typeof c === "string" ? Qt.lighter(c, 1) : c;
        return Qt.rgba(col.r, col.g, col.b, a);
    }

    // Dark or light text, whichever reads better on `c`
    function readableOn(c) {
        const col = typeof c === "string" ? Qt.lighter(c, 1) : c;
        return 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b > 0.55 ? crust : text;
    }

    // Nerd Font glyph by code point, e.g. glyph(0xf057e)
    function glyph(cp) {
        return String.fromCodePoint(cp);
    }
}
