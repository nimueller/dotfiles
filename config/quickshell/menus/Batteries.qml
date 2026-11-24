pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// The batteries UPower knows besides the laptop's own: wireless keyboards,
// mice, headsets and the like, which their kernel drivers report (e.g.
// hid-logitech-hidpp). Shared by the battery menu (battery.qml), its chip in
// the bar (Bar.qml) and the warnings (DeviceBatteryWatch.qml).
Singleton {
    id: root

    // Warnings and colors: at or below these, in percent
    readonly property int lowPercent: 15
    readonly property int criticalPercent: 5
    readonly property int fadingPercent: 30

    readonly property var devices: UPower.devices.values.filter(isDeviceBattery)
    readonly property real lowestPercent: {
        const charges = devices.map(percent);
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

    function isCharging(device) {
        const state = device?.state;
        return state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged;
    }

    // The name to show: the model, else the kind of device ("Keyboard")
    function name(device) {
        if (device.model !== "") {
            return device.model;
        }
        return UPowerDeviceType.toString(device.type);
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
}
