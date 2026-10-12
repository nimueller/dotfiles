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

    // "GPU ... Digital Stereo (HDMI) [Some Monitor]" -> "Some Monitor",
    // "Some Headset ... Receiver Analog Stereo" -> "Some Headset ... Receiver"
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
            return Theme.glyph(0xf00b0); // 󰂰
        if (hint.includes("hdmi") || hint.includes("displayport"))
            return Theme.glyph(0xf0379); // 󰍹
        if (hint.includes("headset") || hint.includes("headphone") || hint.includes("hs80"))
            return Theme.glyph(0xf02cb); // 󰋋
        return node?.isSink ? Theme.glyph(0xf04c3) : Theme.glyph(0xf036c); // 󰓃 / 󰍬
    }

    function volumeIcon(audio) {
        if (!audio || audio.muted || audio.volume <= 0)
            return Theme.glyph(0xf075f); // 󰝟
        if (audio.volume < 0.34)
            return Theme.glyph(0xf057f); // 󰕿
        if (audio.volume < 0.67)
            return Theme.glyph(0xf0580); // 󰖀
        return Theme.glyph(0xf057e); // 󰕾
    }

    function micIcon(audio) {
        return !audio || audio.muted ? Theme.glyph(0xf036d) : Theme.glyph(0xf036c); // 󰍭 / 󰍬
    }

    // The app that owns the stream's process, through its window (Windows.qml):
    // Electron and Chromium apps play from a helper process and all call
    // themselves "Chromium" here. Otherwise what the stream says.
    function owner(node) {
        const pid = parseInt(node.properties["application.process.id"]);
        return pid > 0 ? Windows.entry(Windows.forPid(pid)) : null;
    }

    function appName(node) {
        const p = node.properties;
        return owner(node)?.name || p["application.name"] || node.description || node.name;
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
        const candidates = [owner(node)?.icon, p["application.icon-name"], p["application.process.binary"], name, `${name}-browser`, name.replace(/\s+/g, "-")];
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
