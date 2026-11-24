import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Low batteries of wireless devices (Batteries.qml), part of daemon.qml: the
// warnings of LowBattery.qml for each of them, also on a desktop.
Scope {
    id: root

    // The level each device was last warned about, by name. A device that
    // comes back (a KVM switch or the receiver plugged in again) is a new
    // UPower device and would otherwise warn again about the same charge.
    property var warnedByDevice: ({})

    function remember(deviceName, level) {
        const updated = Object.assign({}, warnedByDevice);
        updated[deviceName] = level;
        warnedByDevice = updated;
    }

    Variants {
        model: Batteries.devices

        delegate: LowBattery {
            required property var modelData
            readonly property string deviceName: Batteries.name(modelData)

            percent: Batteries.percent(modelData)
            isDraining: modelData.state === UPowerDeviceState.Discharging
            isCharging: Batteries.isCharging(modelData)
            lowSummary: I18n.tr("%1: battery low", deviceName)
            criticalSummary: I18n.tr("%1: battery almost empty", deviceName)
            body: I18n.tr("%1% left. Charge it soon.", Math.round(percent))
            // Only the starting value: LowBattery sets it from then on
            warned: root.warnedByDevice[deviceName] ?? noWarning

            onWarnedChanged: root.remember(deviceName, warned)
        }
    }
}
