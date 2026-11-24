import QtQuick
import Quickshell
import Quickshell.Io

// Warns about one battery running low: a notification at Batteries.lowPercent
// and a critical one at Batteries.criticalPercent while it drains, the second
// replacing the first. Each level warns once, until the battery charges.
// Used for the laptop (BatteryWatch.qml) and the wireless devices
// (DeviceBatteryWatch.qml).
Scope {
    id: root

    required property real percent
    required property bool isDraining
    // Only charging starts the warnings over: a device that reconnects
    // reports neither charging nor draining for a moment
    required property bool isCharging
    required property string lowSummary
    required property string criticalSummary
    // The text of the notification, read when it's sent
    required property string body

    readonly property int noWarning: 0
    readonly property int lowWarning: 1
    readonly property int criticalWarning: 2

    readonly property int level: {
        if (!isDraining) {
            return noWarning;
        }
        if (percent <= Batteries.criticalPercent) {
            return criticalWarning;
        }
        if (percent <= Batteries.lowPercent) {
            return lowWarning;
        }
        return noWarning;
    }
    // The highest level warned about since the battery last charged
    property int warned: noWarning
    property int notificationId: 0

    onLevelChanged: check()
    onIsChargingChanged: check()
    Component.onCompleted: check()

    function check() {
        if (isCharging) {
            warned = noWarning;
            return;
        }
        if (level > warned) {
            warned = level;
            notify();
        }
    }

    function notify() {
        const isCritical = level === criticalWarning;
        const urgency = isCritical ? "critical" : "normal";
        const icon = isCritical ? "battery-empty" : "battery-caution";
        const summary = isCritical ? criticalSummary : lowSummary;
        const replace = ["-p", "-r", String(notificationId)];
        notifySend.command = ["notify-send", ...replace, "-a", "Battery", "-u", urgency, "-i", icon, summary, body];
        notifySend.running = true;
    }

    Process {
        id: notifySend
        stdout: StdioCollector {
            onStreamFinished: root.notificationId = parseInt(text) || 0
        }
    }
}
