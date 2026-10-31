// Software rendering: on the NVIDIA driver every GPU-rendered window costs
// its own context and buffers, ~100 MB per bar; this simple UI draws fine on
// the CPU and the daemon needs ~200 MB instead of ~490 MB.
//@ pragma Env QT_QUICK_BACKEND=software
// The icons of the GTK desktop (adwaita-icon-theme): without a theme, Qt
// looks only in hicolor, which has the apps' icons but not the devices'
// (the launcher's "scanner", "video-display")
//@ pragma IconTheme Adwaita
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Resident part of the desktop shell (started with Hyprland, see
// autostart.lua; also D-Bus activated for notifications): the bar on every
// monitor, the app launcher, the clipboard history, the notification daemon with
// its popups and center (replaces dunst), the OSD for the volume and
// brightness keys (replaces SwayOSD), the stay-awake inhibitor, the
// camera/microphone/screen-sharing watch, the KDE Connect phones, the
// night light's schedule, the Bluetooth pairing agent, the fixed folders in Files' sidebar and the
// warnings about a full memory, an overloaded CPU, a full disk or a low
// battery. The bar menus and the
// windows opened from them live here too, created only while open
// (Menus.qml).
//
//   toggle.sh audio|battery|...        open/close a menu (Menus.names)
//   SUPER+D / toggle.sh launcher       show/hide the launcher
//   SUPER+V / toggle.sh clipboard      show/hide the clipboard history
//   toggle.sh notifications            open/close the notification center
//   ipc.sh notifications dnd|clear     do not disturb / clear all from scripts
//   hl.dsp.event("quickshell-osd volume +5")    keybinds.lua: volume +/-N,
//                                      mute, mic-mute, brightness +/-N,
//                                      lock caps|num
//   hl.dsp.event("quickshell-awake sunshine on")  the stay-awake script: on|off
ShellRoot {
    // No live reload: reloading while it holds the notification service and
    // the tray made the next exit hang. Apply changes with
    // `toggle.sh daemon --restart`.
    settings.watchFiles: false

    Component.onCompleted: Menus.hosted = true


    NotificationStore {
        id: notificationStore
        sharing: privacyStatus.screen // no popups on a shared screen
    }

    NotificationPopups {
        store: notificationStore
    }

    NotificationCenter {
        id: notificationCenter
        store: notificationStore
    }

    Osd {
        id: osd
    }

    // No idle lock while videos play, games run or Sunshine streams
    StayAwake {
        id: stayAwake
        osd: osd
    }

    Launcher {}

    Clipboard {}

    NetworkStatus {
        id: networkStatus
    }

    // Microphone, camera and screen sharing in use
    Privacy {
        id: privacyStatus
        osd: osd
    }

    // Which apps use them, from the bar's privacy chip
    PrivacyPanel {
        id: privacyApps
        privacy: privacyStatus
    }

    // The Bluetooth pairing agent (bluetooth-agent.py), all the time
    readonly property var bluetoothAgent: BluetoothAgent

    // KDE Connect phones for the bar (kdeconnect.py)
    PhoneStatus {
        id: phoneStatus
    }

    // Notifications with Open and Eject for USB drives, discs and phones
    // (drives.py, with the system's Python for GVfs)
    Process {
        id: drives
        running: true
        command: ["/usr/bin/python3", Quickshell.shellPath("drives.py")]
        onExited: drivesRestart.start()
    }
    Timer {
        id: drivesRestart
        interval: 5000
        onTriggered: drives.running = true
    }

    // Notifications when memory, the CPU or the disk run out
    SystemWatch {}

    // Laptops: notifications when the battery runs low
    BatteryWatch {}

    // Laptops: the charge, power draw and the apps' CPU time on battery,
    // once a minute for the battery history (battery-log.py)
    Process {
        id: batteryLog
        running: Modes.laptop
        command: ["/usr/bin/python3", Quickshell.shellPath("battery-log.py")]
        onExited: if (Modes.laptop) batteryLogRestart.start()
    }
    Timer {
        id: batteryLogRestart
        interval: 5000
        onTriggered: batteryLog.running = Modes.laptop
    }

    // The night light on its schedule (night-light.py, hyprsunset)
    Process {
        id: nightLight
        running: true
        command: ["/usr/bin/python3", Quickshell.shellPath("night-light.py")]
        onExited: nightLightRestart.start()
    }
    Timer {
        id: nightLightRestart
        interval: 5000
        onTriggered: nightLight.running = true
    }

    // Downloads, Documents etc. stay in Files' sidebar (bookmarks.py)
    Process {
        id: bookmarks
        running: true
        command: ["/usr/bin/python3", Quickshell.shellPath("bookmarks.py")]
        onExited: bookmarksRestart.start()
    }
    Timer {
        id: bookmarksRestart
        interval: 5000
        onTriggered: bookmarks.running = true
    }

    // The bar on every monitor
    Variants {
        model: Quickshell.screens

        delegate: Bar {
            required property var modelData

            screen: modelData
            store: notificationStore
            center: notificationCenter
            network: networkStatus
            privacy: privacyStatus
            privacyPanel: privacyApps
            phones: phoneStatus
        }
    }

    IpcHandler {
        target: "menus"

        function toggle(name: string): void {
            Menus.toggle(name);
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            notificationCenter.toggle();
        }
        function dnd(): void {
            notificationStore.setDnd(!notificationStore.dnd);
        }
        function clear(): void {
            notificationStore.clear();
        }
    }

    // Keys send events instead of starting a process for each press
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "custom" && event.data.startsWith("quickshell-awake ")) {
                const [, name, state] = event.data.split(" ");
                stayAwake.event(name, state);
                return;
            }
            if (event.name !== "custom" || !event.data.startsWith("quickshell-osd "))
                return;
            const [, what, arg] = event.data.split(" ");
            if (what === "volume")
                osd.volume(parseInt(arg));
            else if (what === "mute")
                osd.toggleMute();
            else if (what === "mic-mute")
                osd.toggleMic();
            else if (what === "brightness")
                osd.brightness(parseInt(arg));
            else if (what === "lock")
                osd.lockKey(arg);
        }
    }
}
