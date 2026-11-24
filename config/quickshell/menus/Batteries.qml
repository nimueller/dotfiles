pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The batteries of wireless devices besides the laptop's own: keyboards,
// mice, headsets and the like. UPower knows those their kernel drivers
// report (e.g. hid-logitech-hidpp), corsair-battery.py Corsair's headsets
// and mice. Shared by the battery menu (battery.qml), its chip in the bar
// (Bar.qml) and the warnings (DeviceBatteryWatch.qml).
//
// Each entry of `devices` is { name, percent, isCharging, isDraining }.
Singleton {
    id: root

    // Warnings and colors: at or below these, in percent
    readonly property int lowPercent: 15
    readonly property int criticalPercent: 5
    readonly property int fadingPercent: 30

    // Corsair's batteries change slowly, and each look asks the devices
    readonly property int corsairInterval: 120000 // ms

    readonly property var upowerDevices: UPower.devices.values.filter(isDeviceBattery)
    // As corsair-battery.py prints them
    property var corsairDevices: []

    readonly property var devices: {
        const all = [];
        for (const device of upowerDevices) {
            all.push(fromUPower(device));
        }
        for (const device of corsairDevices) {
            all.push(fromCorsair(device));
        }
        return all;
    }
    readonly property real lowestPercent: {
        const charges = devices.map(device => device.percent);
        return charges.length > 0 ? Math.min(...charges) : 100;
    }

    // UPower's percentage, which some versions give from 0 to 1, from 0 to 100
    function percent(device) {
        if (!device) {
            return 0;
        }
        if (device.percentage <= 1) {
            return device.percentage * 100;
        }
        return device.percentage;
    }

    // A device with a battery of its own: not the laptop's battery, not a
    // power supply, and one that reports a charge
    function isDeviceBattery(device) {
        if (device.isLaptopBattery) {
            return false;
        }
        if (!device.isPresent) {
            return false;
        }
        const isLinePower = device.type === UPowerDeviceType.LinePower;
        const isSystemBattery = device.type === UPowerDeviceType.Battery;
        if (isLinePower || isSystemBattery) {
            return false;
        }
        return device.percentage > 0;
    }

    function fromUPower(device) {
        const state = device.state;
        const isCharging = state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged;
        return {
            name: upowerName(device),
            percent: percent(device),
            isCharging: isCharging,
            isDraining: state === UPowerDeviceState.Discharging
        };
    }

    function fromCorsair(device) {
        return {
            name: corsairName(device),
            percent: device.percent,
            isCharging: device.state === "charging",
            isDraining: device.state === "discharging"
        };
    }

    // The name to show: the model, else the kind of device ("Keyboard")
    function upowerName(device) {
        if (device.model !== "") {
            return device.model;
        }
        return UPowerDeviceType.toString(device.type);
    }

    function corsairName(device) {
        if (device.model !== "") {
            return device.model;
        }
        if (device.kind === "headset") {
            return I18n.tr("Headset");
        }
        return I18n.tr("Mouse");
    }

    // Red when low, yellow when fading, green otherwise
    function chargeColor(charge) {
        if (charge <= lowPercent) {
            return Theme.red;
        }
        if (charge <= fadingPercent) {
            return Theme.yellow;
        }
        return Theme.green;
    }

    Process {
        id: corsairProbe

        command: [Quickshell.shellPath("corsair-battery.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.corsairDevices = JSON.parse(text).devices;
                } catch (error) {
                    // It printed why on stderr; keep the last answer
                    console.warn(`corsair-battery.py: ${error}`);
                }
            }
        }
    }

    Timer {
        interval: root.corsairInterval
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: corsairProbe.running = true
    }
}
