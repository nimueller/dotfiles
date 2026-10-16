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
    readonly property real percent: battery ? (battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 100
    readonly property bool discharging: Modes.laptop && !!battery && battery.isLaptopBattery && battery.state === UPowerDeviceState.Discharging
    readonly property int level: !discharging ? 0 : percent <= 5 ? 2 : percent <= 15 ? 1 : 0
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
            notify.command = ["notify-send", "-p", "-r", String(nid), "-a", "Battery", "-u", level === 2 ? "critical" : "normal", "-i", level === 2 ? "battery-empty" : "battery-caution", level === 2 ? "Battery almost empty" : "Battery low", `${Math.round(percent)} %${left}. Plug in the charger.`];
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
