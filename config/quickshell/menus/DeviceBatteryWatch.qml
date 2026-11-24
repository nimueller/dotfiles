import QtQuick
import Quickshell

// Low batteries of wireless devices (Batteries.qml), part of daemon.qml: the
// warnings of LowBattery.qml for each of them, also on a desktop.
Scope {
    id: root

    // The level each device was last warned about, by key. A device that
    // comes back (a KVM switch or the receiver plugged in again) is a new
    // device and would otherwise warn again about the same charge.
    property var warnedByDevice: ({})

    function remember(key, level) {
        const updated = Object.assign({}, warnedByDevice);
        updated[key] = level;
        warnedByDevice = updated;
    }

    // The device of a key, or one that has just gone
    function find(key) {
        const device = Batteries.devices.find(candidate => candidate.key === key);
        return device ?? {
            name: key,
            percent: 100,
            isCharging: false,
            isDraining: false
        };
    }

    // By key: Batteries.devices are new objects at every change, which
    // would make each warning anew and lose the notification it replaces
    Variants {
        model: Batteries.devices.map(device => device.key)

        delegate: LowBattery {
            required property string modelData
            readonly property var device: root.find(modelData)
            readonly property string deviceName: device.name

            percent: device.percent
            isDraining: device.isDraining
            isCharging: device.isCharging
            lowSummary: I18n.tr("%1: battery low", deviceName)
            criticalSummary: I18n.tr("%1: battery almost empty", deviceName)
            body: I18n.tr("%1% left. Charge it soon.", Math.round(percent))
            // Only the starting value: LowBattery sets it from then on
            warned: root.warnedByDevice[modelData] ?? noWarning

            onWarnedChanged: root.remember(modelData, warned)
        }
    }
}
