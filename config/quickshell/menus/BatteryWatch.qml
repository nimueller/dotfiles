import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Low battery, part of daemon.qml (laptop mode): the warnings of
// LowBattery.qml for the laptop's own battery. At about 2 % UPower itself
// hibernates or shuts down (CriticalPowerAction in /etc/UPower/UPower.conf).
LowBattery {
    readonly property var battery: UPower.displayDevice
    readonly property bool isOwnBattery: !!battery && battery.isLaptopBattery
    readonly property string timeLeft: {
        if (!battery || battery.timeToEmpty <= 0) {
            return "";
        }
        const minutes = Math.round(battery.timeToEmpty / 60);
        return I18n.tr(", about %1 min left", minutes);
    }

    percent: isOwnBattery ? Batteries.percent(battery) : 100
    isDraining: Modes.laptop && isOwnBattery && battery.state === UPowerDeviceState.Discharging
    // A laptop that isn't draining is plugged in
    isCharging: !isDraining
    lowSummary: I18n.tr("Battery low")
    criticalSummary: I18n.tr("Battery almost empty")
    body: I18n.tr("%1 %%2. Plug in the charger.", Math.round(percent), timeLeft)
}
