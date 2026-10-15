import QtQuick
import Quickshell
import Quickshell.Io

// Warns with a notification when the system is in trouble, part of
// daemon.qml; checks every 15 seconds:
//  - Memory: little left (MemAvailable) or the kernel is busy reclaiming
//    (memory pressure, /proc/pressure/memory), critical. Names the program
//    with the most memory (all its processes together).
//  - CPU: tasks have waited for a CPU most of the last minute (CPU pressure,
//    /proc/pressure/cpu), for a while; a busy CPU alone doesn't count.
//    Names the busiest program.
//  - Disk: little space left on /, two warnings and then a critical one.
// The limits come from Machine Settings (LocalSettings.qml). Each warns
// once, then again only after it has been fine for a while, or after the
// screen is unlocked (at login too): nothing shows while it's locked, and
// what's still wrong then shows again, replacing its earlier notification.
// "Show" opens btop, or gdu/ncdu (Files without them) for the disk.
Scope {
    id: root

    readonly property real gib: 1073741824
    readonly property var limits: LocalSettings.warnings
    readonly property string btop: "kitty --class btop -e btop"

    property bool locked: false
    property bool memoryAlert: false
    property real cpuSince: 0 // since when the CPU's pressure is high (ms)
    property bool cpuAlert: false
    property int diskLevel: 0 // 0 fine, else the level (1..) warned about

    // New limits count from scratch
    property string limitsText: ""
    Component.onCompleted: limitsText = JSON.stringify(limits)
    onLimitsChanged: {
        const text = JSON.stringify(limits);
        if (text !== limitsText)
            reset();
        limitsText = text;
    }

    function reset() {
        memoryAlert = false;
        cpuAlert = false;
        diskLevel = 0;
    }

    // Free bytes below which a disk this size is at a level (1..)
    function diskLimit(level, size) {
        const l = limits.disk.levels[level - 1];
        return Math.min(l.percent / 100 * size, l.gb * gib);
    }

    function size(bytes) {
        return bytes >= 10 * gib ? `${Math.round(bytes / gib)} GB` : `${(bytes / gib).toFixed(1)} GB`;
    }

    // One notification each, replaced when it warns again while still open
    component Alert: Process {
        id: alert

        property int nid: 0
        property string show: ""
        property bool restart: false

        // body, then the output of the top command, which only runs when it warns
        function send(urgency, icon, summary, body, top, show) {
            this.show = show;
            command = ["sh", "-c", `top=$(sh -c "$5" 2>/dev/null)
exec notify-send -p -r "$6" -a System -u "$1" -i "$2" -A show=Show -- "$3" "$4$top"`, "sh", urgency, icon, summary, body, top, String(nid)];
            // The one waiting for the earlier notification goes first
            if (running) {
                restart = true;
                running = false;
            } else {
                running = true;
            }
        }

        // The notification's id right away, then the action once it's closed
        stdout: SplitParser {
            onRead: line => {
                if (/^\d+$/.test(line))
                    alert.nid = Number(line);
                else if (line === "show")
                    Quickshell.execDetached(["sh", "-c", alert.show]);
            }
        }
        onExited: {
            if (restart) {
                restart = false;
                running = true;
            } else {
                nid = 0; // closed
            }
        }
    }

    Alert {
        id: memoryNote
    }
    Alert {
        id: cpuNote
    }
    Alert {
        id: diskNote
    }

    function check(text) {
        const v = {};
        for (const line of text.trim().split("\n")) {
            const f = line.trim().split(/\s+/);
            v[f[0].replace(/:$/, "")] = f.slice(1).map(Number);
        }
        // Wait for the unlock, and then tell again what's still wrong
        const wasLocked = locked;
        locked = "locked" in v;
        if (locked)
            return;
        if (wasLocked)
            reset();
        if (!v.MemTotal || !v.disk)
            return;

        const available = v.MemAvailable[0] / v.MemTotal[0];
        const stalled = v.memory?.[0] ?? 0;
        if (!limits.memory.on) {
            memoryAlert = false;
        } else if (!memoryAlert && (available < limits.memory.percent / 100 || stalled >= 10)) {
            memoryAlert = true;
            memoryNote.send("critical", "dialog-warning", "Memory is almost full", `${size(v.MemAvailable[0] * 1024)} of ${size(v.MemTotal[0] * 1024)} left, the system may freeze. Most memory: `, `ps -eo rss=,comm= | awk '{r=$1; $1=""; m[substr($0,2)]+=r} END {for (c in m) print m[c], c}' | sort -rn | awk '{r=$1; $1=""; printf "%s (%.1f GB)", substr($0,2), r/1048576; exit}'`, btop);
        } else if (memoryAlert && available > 2 * limits.memory.percent / 100 && stalled < 2) {
            memoryAlert = false;
        }

        const cpu = v.cpu?.[0] ?? 0;
        if (cpu < limits.cpu.percent)
            cpuSince = 0;
        else if (!cpuSince)
            cpuSince = Date.now();
        if (!limits.cpu.on) {
            cpuAlert = false;
        } else if (!cpuAlert && cpuSince && Date.now() - cpuSince >= limits.cpu.minutes * 60000) {
            cpuAlert = true;
            cpuNote.send("normal", "dialog-warning", "The system is overloaded", `Programs have waited for the CPU ${Math.round(cpu)} % of the last minute. Busiest: `, `LC_ALL=C top -b -n 2 -d 1 -o %CPU -w 512 | awk '/^ *PID/ {n++; next} n == 2 && NF {c=$12; for (i=13; i<=NF; i++) c=c" "$i; print c" ("int($9)" %)"; exit}'`, btop);
        } else if (cpuAlert && cpu < limits.cpu.percent / 2) {
            cpuAlert = false;
        }

        const [free, total] = v.disk;
        const levels = limits.disk.levels.length;
        let level = 0;
        for (let i = levels; i > 0 && !level; i--)
            if (free < diskLimit(i, total))
                level = i;
        if (!limits.disk.on) {
            diskLevel = 0;
        } else if (level > diskLevel) {
            const critical = level === levels;
            const summary = critical ? "The disk is full" : level > 1 ? "The disk is almost full" : "The disk is filling up";
            diskNote.send(critical ? "critical" : "normal", "drive-harddisk", summary, `${size(free)} (${Math.round(100 * free / total)} %) free on /.`, "", 'for t in gdu ncdu; do command -v $t >/dev/null && exec kitty --class disk-usage -e $t -x ~; done; exec nautilus ~');
            diskLevel = level;
        } else if (level < diskLevel && free > diskLimit(diskLevel, total) + 2 * gib) {
            // Fine again with a margin, so a disk at the limit warns only once
            diskLevel = level;
        }
    }

    // MemTotal/MemAvailable in kB, the pressures' avg10 (memory, full) and
    // avg60 (cpu, some) in %, the free and total bytes on /, and whether the
    // lock screen is up
    Process {
        id: probe

        command: ["sh", "-c", `grep -E '^(MemTotal|MemAvailable):' /proc/meminfo
sed -n 's/^full avg10=\\([0-9.]*\\).*/memory \\1/p' /proc/pressure/memory 2>/dev/null
sed -n 's/^some avg10=[0-9.]* avg60=\\([0-9.]*\\).*/cpu \\1/p' /proc/pressure/cpu 2>/dev/null
df -B1 --output=avail,size / | tail -1 | sed 's/^/disk /'
pgrep -xu "$(id -u)" hyprlock >/dev/null && echo locked`]
        stdout: StdioCollector {
            onStreamFinished: root.check(text)
        }
    }

    // More often while locked, to tell right after the unlock
    Timer {
        interval: root.locked ? 2000 : 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
}
