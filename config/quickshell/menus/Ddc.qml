import QtQuick
import Quickshell
import Quickshell.Io

// Brightness of external monitors over DDC/CI (ddcutil): the OSD's
// brightness keys on machines without a backlight, and the system menu's
// sliders. The monitor's own menu must have DDC/CI switched on. ddcutil is
// slow (a few hundred ms per call), so changes show at once and only the
// latest value is sent. Another process (the menu or the keys) may have
// changed it meanwhile, so a value older than a few seconds is read again
// before a step. ddcutil detect takes about a second, so what it found is
// kept in $XDG_RUNTIME_DIR/quickshell-ddc.json for the same set of screens:
// the menu shows the sliders at once and only reads the values again.
Scope {
    id: root

    // Connector name (DP-1) → { bus, model, value, max, time }
    property var displays: ({})
    readonly property var names: Object.keys(displays).sort()
    readonly property bool loading: detect.running // looking for monitors
    readonly property string screens: Array.from(Quickshell.screens, s => s.name).sort().join(" ")
    property var pending: ({}) // connector → value still to send
    property var steps: ({}) // connector → percent to add once read again

    signal changed(string name, real value) // value 0..1

    function has(name) {
        return !!displays[name];
    }

    function value(name) {
        const d = displays[name];
        return d ? d.value / d.max : 0;
    }

    function set(name, fraction) {
        const d = displays[name];
        d.value = Math.round(Math.max(0, Math.min(1, fraction)) * d.max);
        d.time = Date.now();
        pending[name] = d.value;
        displaysChanged();
        changed(name, d.value / d.max);
        flush();
        saveTimer.restart();
    }

    // step in percent
    function step(name, percent) {
        const d = displays[name];
        if (Date.now() - d.time < 5000) {
            set(name, (d.value + percent * d.max / 100) / d.max);
            return;
        }
        steps[name] = (steps[name] ?? 0) + percent;
        flush();
    }

    // One ddcutil at a time: re-reads first, then the latest values
    function flush() {
        if (ddc.running)
            return;
        const read = Object.keys(steps)[0];
        if (read !== undefined) {
            ddc.reading = read;
            ddc.started = Date.now();
            ddc.command = ["ddcutil", "--bus", displays[read].bus, "-t", "getvcp", "10"];
            ddc.running = true;
            return;
        }
        const name = Object.keys(pending)[0];
        if (name === undefined)
            return;
        ddc.reading = "";
        ddc.command = ["ddcutil", "--bus", displays[name].bus, "--noverify", "setvcp", "10", String(pending[name])];
        delete pending[name];
        ddc.running = true;
    }

    // "<bus> <connector> VCP 10 C <current> <max> <model>" for each monitor
    // that answers on DDC/CI
    Process {
        id: detect
        command: ["sh", "-c", `
            ddcutil detect --brief 2>/dev/null |
                awk '/^Display/ { d = 1 } /^Invalid/ { d = 0 }
                     d && /I2C bus/ { bus = $3 } d && /DRM connector/ { conn = $3 }
                     d && /Monitor:/ { sub(/^ *Monitor: */, ""); split($0, m, ":"); print bus, conn, m[2] }' |
                while read -r bus conn model; do
                    n=\${bus#/dev/i2c-}
                    echo "$n \${conn#card*-} $(ddcutil --bus "$n" -t getvcp 10 2>/dev/null) $model"
                done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f.length >= 7 && f[2] === "VCP" && parseInt(f[6]) > 0)
                        found[f[1]] = { bus: f[0], model: f.slice(7).join(" "), value: parseInt(f[5]), max: parseInt(f[6]), time: Date.now() };
                }
                root.displays = found;
                root.save();
            }
        }
    }

    function save() {
        cacheFile.setText(JSON.stringify({ screens: screens, displays: displays }));
    }

    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: root.save()
    }

    // The monitors found before for these screens, else detect them. Their
    // values may have changed meanwhile (the keys, the monitor's own menu),
    // so they're read again.
    FileView {
        id: cacheFile
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/quickshell-ddc.json`
        blockLoading: true
        printErrors: false
        onLoaded: {
            let cached = null;
            try {
                cached = JSON.parse(text());
            } catch (e) {}
            if (cached?.screens !== root.screens || !cached.displays) {
                detect.running = true;
                return;
            }
            for (const name in cached.displays) {
                cached.displays[name].time = 0;
                root.steps[name] = 0;
            }
            root.displays = cached.displays;
            root.flush();
        }
        onLoadFailed: detect.running = true
    }

    Process {
        id: ddc

        property string reading: "" // connector whose value is read again
        property real started: 0 // when that read started

        stdout: StdioCollector {
            onStreamFinished: {
                const name = ddc.reading;
                if (!name)
                    return;
                const d = root.displays[name];
                const f = text.trim().split(/\s+/); // VCP 10 C <current> <max>
                const percent = root.steps[name] ?? 0;
                delete root.steps[name];
                if (f[0] !== "VCP" || !(parseInt(f[4]) > 0)) {
                    // Gone or on another bus since it was cached
                    detect.running = true;
                    return;
                }
                // Moved in the menu while reading: that value wins
                if (d.time > ddc.started && !percent)
                    return;
                d.value = parseInt(f[3]);
                d.max = parseInt(f[4]);
                d.time = Date.now();
                if (percent) {
                    root.set(name, (d.value + percent * d.max / 100) / d.max);
                    return;
                }
                root.displaysChanged(); // no changed(): not a change to show in the OSD
            }
        }
        onExited: root.flush()
    }

    // Monitors plugged in or out
    Connections {
        target: Quickshell

        function onScreensChanged() {
            detect.running = true;
        }
    }
}
