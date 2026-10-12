import QtQuick
import Quickshell
import Quickshell.Io

// Brightness of external monitors over DDC/CI (ddcutil), for the OSD's
// brightness keys on machines without a backlight. The monitor's own menu
// must have DDC/CI switched on. ddcutil is slow (a few hundred ms per call),
// so key presses update the value at once and only the latest one is sent.
Scope {
    id: root

    // Connector name (DP-1) → { bus, value, max }
    property var displays: ({})
    property var pending: ({}) // connector → value still to send

    function has(name) {
        return !!displays[name];
    }

    // step in percent; returns the new brightness (0..1)
    function step(name, percent) {
        const d = displays[name];
        d.value = Math.max(0, Math.min(d.max, Math.round(d.value + percent * d.max / 100)));
        pending[name] = d.value;
        flush();
        return d.value / d.max;
    }

    function flush() {
        if (setter.running)
            return;
        const name = Object.keys(pending)[0];
        if (name === undefined)
            return;
        setter.command = ["ddcutil", "--bus", displays[name].bus, "--noverify", "setvcp", "10", String(pending[name])];
        delete pending[name];
        setter.running = true;
    }

    // "<bus> <connector> VCP 10 C <current> <max>" for each monitor that
    // answers on DDC/CI
    Process {
        id: detect
        running: true
        command: ["sh", "-c", `
            ddcutil detect --brief 2>/dev/null |
                awk '/^Display/ { d = 1 } /^Invalid/ { d = 0 } d && /I2C bus/ { bus = $3 } d && /DRM connector/ { print bus, $3 }' |
                while read -r bus conn; do
                    n=\${bus#/dev/i2c-}
                    echo "$n \${conn#card*-} $(ddcutil --bus "$n" -t getvcp 10 2>/dev/null)"
                done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f.length >= 7 && f[2] === "VCP" && parseInt(f[6]) > 0)
                        found[f[1]] = { bus: f[0], value: parseInt(f[5]), max: parseInt(f[6]) };
                }
                root.displays = found;
            }
        }
    }

    Process {
        id: setter
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
