pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Node lists and display helpers shared by the sections.
Singleton {
    readonly property var sinks: devices(true)
    readonly property var sources: devices(false)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)
    readonly property var recordings: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)

    function devices(sink) {
        return Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink === sink);
    }

    function glyph(cp) {
        return String.fromCodePoint(cp);
    }

    // "AD103 ... Digital Stereo (HDMI) [BenQ EL2870U]" -> "BenQ EL2870U",
    // "CORSAIR HS80 ... Receiver Analog Stereo" -> "CORSAIR HS80 ... Receiver"
    function deviceName(node) {
        if (!node)
            return "No device";
        const desc = (node.description || node.nickname || node.name).replace(/[\x00-\x1f]/g, "");
        const bracket = desc.match(/\[(.+)\]\s*$/);
        if (bracket)
            return bracket[1];
        return desc.replace(/\s+(Analog|Digital|Pro)?\s*(Stereo|Mono|Surround[\s\d.]*)(\s*\(.*\))?$/i, "") || desc;
    }

    function deviceIcon(node) {
        const p = node?.properties ?? {};
        const hint = `${p["device.form-factor"] ?? ""} ${node?.name ?? ""} ${node?.description ?? ""}`.toLowerCase();
        if (hint.includes("bluez"))
            return glyph(0xf00b0); // 󰂰
        if (hint.includes("hdmi") || hint.includes("displayport"))
            return glyph(0xf0379); // 󰍹
        if (hint.includes("headset") || hint.includes("headphone") || hint.includes("hs80"))
            return glyph(0xf02cb); // 󰋋
        return node?.isSink ? glyph(0xf04c3) : glyph(0xf036c); // 󰓃 / 󰍬
    }

    function volumeIcon(audio) {
        if (!audio || audio.muted || audio.volume <= 0)
            return glyph(0xf075f); // 󰝟
        if (audio.volume < 0.34)
            return glyph(0xf057f); // 󰕿
        if (audio.volume < 0.67)
            return glyph(0xf0580); // 󰖀
        return glyph(0xf057e); // 󰕾
    }

    function micIcon(audio) {
        return !audio || audio.muted ? glyph(0xf036d) : glyph(0xf036c); // 󰍭 / 󰍬
    }

    function appName(node) {
        const p = node.properties;
        return p["application.name"] || node.description || node.name;
    }

    // Media title, unless it's one of the generic names apps like to send.
    function mediaName(node) {
        const media = node.properties["media.name"] ?? "";
        const generic = ["audiostream", "playback", "audio stream", "output", ""];
        return generic.includes(media.toLowerCase()) || media === appName(node) ? "" : media;
    }

    function appIcon(node) {
        const p = node.properties;
        const name = appName(node).toLowerCase();
        const candidates = [p["application.icon-name"], p["application.process.binary"], name, `${name}-browser`, name.replace(/\s+/g, "-")];
        for (const c of candidates) {
            const path = c ? Quickshell.iconPath(c, true) : "";
            if (path)
                return path;
        }
        return "";
    }

    // Make `node` the default device and move running streams onto it. Streams
    // that were ever moved by hand (e.g. in pavucontrol) are pinned to that
    // device by WirePlumber and would otherwise ignore the new default.
    function setDefault(node) {
        if (node.isSink)
            Pipewire.preferredDefaultAudioSink = node;
        else
            Pipewire.preferredDefaultAudioSource = node;
        for (const stream of node.isSink ? streams : recordings)
            Quickshell.execDetached(["pw-metadata", String(stream.id), "target.object", node.name]);
    }

    function setVolume(node, v) {
        if (node?.audio)
            node.audio.volume = Math.max(0, Math.min(1, v));
    }
}
