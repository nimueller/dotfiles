pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Node lists and display helpers shared by the sections.
Singleton {
    readonly property var sinks: devices(true)
    readonly property var sources: devices(false)
    readonly property var streams: visible().filter(n => n.isStream && n.isSink)
    readonly property var recordings: visible().filter(n => n.isStream && !n.isSink)

    // Every audio node, hidden or not, for the menu's PwObjectTracker. A node's
    // properties (and so `dotfiles.hidden`) only arrive once it is bound; were
    // only the visible ones tracked, a hidden node would drop out as soon as
    // it was bound, lose its properties, show up again, get bound again, ...
    readonly property var all: Pipewire.nodes.values.filter(n => n.audio)

    function devices(sink) {
        return visible().filter(n => !n.isStream && n.isSink === sink);
    }

    // Nodes with `dotfiles.hidden = true` belong to a filter-chain's plumbing,
    // e.g. speakers that are only fed through a protection filter.
    function visible() {
        return Pipewire.nodes.values.filter(n => n.audio && n.properties["dotfiles.hidden"] !== "true");
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

    // A stream's properties, over those of its PipeWire client: some streams
    // don't say which app they're from, only their client does (OpenAL Soft).
    // Quickshell has no clients, so pw-dump reads them
    // when such a stream from a client not read yet turns up.
    property var clients: ({}) // client id → properties
    function props(node) {
        return Object.assign({}, clients[node.properties["client.id"]], node.properties);
    }

    readonly property bool clientsMissing: streams.concat(recordings).some(n => {
        const id = n.properties["client.id"];
        return id && !n.properties["application.process.id"] && !(id in clients);
    })
    onClientsMissingChanged: if (clientsMissing)
        clientDump.running = true

    Process {
        id: clientDump
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                let objects = [];
                try {
                    objects = JSON.parse(text);
                } catch (e) {}
                const map = {};
                for (const o of objects)
                    if (o.type === "PipeWire:Interface:Client")
                        map[o.id] = o.info?.props ?? {};
                clients = map;
            }
        }
    }

    // The app that owns the stream's process, through its window (Windows.qml):
    // Electron and Chromium apps play from a helper process and all call
    // themselves "Chromium" here. Flatpaks send their PID inside the sandbox,
    // which matches no window; their icon name is usually the window class
    // (Brave: "brave-browser"). Otherwise what the stream says.
    function owner(node) {
        const p = props(node);
        const pid = parseInt(p["application.process.id"]);
        const window = (pid > 0 ? Windows.forPid(pid) : null) ?? Windows.forApp(p["application.icon-name"]);
        return Windows.entry(window);
    }

    function appName(node) {
        const p = props(node);
        return owner(node)?.name || p["application.name"] || node.description || node.name;
    }

    // Media title, unless it's one of the generic names apps like to send.
    function mediaName(node) {
        const media = node.properties["media.name"] ?? "";
        const generic = ["audiostream", "playback", "audio stream", "output", ""];
        return generic.includes(media.toLowerCase()) || media === appName(node) ? "" : media;
    }

    // The app's icon, or else that of the program that started it
    function appIcon(node) {
        const p = props(node);
        const name = appName(node).toLowerCase();
        const pid = parseInt(p["application.process.id"]);
        const candidates = [owner(node)?.icon, p["application.icon-name"], p["application.process.binary"], name, `${name}-browser`, name.replace(/\s+/g, "-"), pid > 0 ? Windows.launcherEntry(pid)?.icon : ""];
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
