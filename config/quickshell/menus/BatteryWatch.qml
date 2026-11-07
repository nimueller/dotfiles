import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Low battery, part of daemon.qml (laptop mode): a notification at 15 %
// and a critical one at 5 % while it discharges, the second replacing the
// first. Plugging in resets it. At about 2 % UPower itself hibernates or
// shuts down (CriticalPowerAction in /etc/UPower/UPower.conf).
Scope {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property real percent: {
        if (battery) {
            if (battery.percentage <= 1) {
                return battery.percentage * 100;
            }
            return battery.percentage;
        }
        return 100;
    }
    readonly property bool isOwnBattery: !!battery && battery.isLaptopBattery
    readonly property bool discharging: Modes.laptop && isOwnBattery && battery.state === UPowerDeviceState.Discharging
    readonly property int level: {
        if (!discharging) {
            return 0;
        }
        if (percent <= 5) {
            return 2;
        }
        if (percent <= 15) {
            return 1;
        }
        return 0;
    }
    property int warned: 0
    property int nid: 0

    onLevelChanged: check()
    Component.onCompleted: check()

    function check() {
        if (!discharging) {
            warned = 0;
        } else if (level > warned) {
            warned = level;
            const left = battery.timeToEmpty > 0 ? `, about ${Math.round(battery.timeToEmpty / 60)} min left` : "";
            const isCritical = level === 2;
            const urgency = isCritical ? "critical" : "normal";
            const icon = isCritical ? "battery-empty" : "battery-caution";
            const summary = isCritical ? "Battery almost empty" : "Battery low";
            const body = `${Math.round(percent)} %${left}. Plug in the charger.`;
            const replace = ["-p", "-r", String(nid)];
            notify.command = ["notify-send", ...replace, "-a", "Battery", "-u", urgency, "-i", icon, summary, body];
            notify.running = true;
        }
    }

    Process {
        id: notify
        stdout: StdioCollector {
            onStreamFinished: root.nid = parseInt(text) || 0
        }
    }
}
