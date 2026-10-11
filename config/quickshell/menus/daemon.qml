// Software rendering: on the NVIDIA driver every GPU-rendered window costs
// its own context and buffers, ~100 MB per bar; this simple UI draws fine on
// the CPU and the daemon needs ~200 MB instead of ~490 MB.
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Resident part of the desktop shell (started with Hyprland, see
// autostart.lua; also D-Bus activated for notifications): the bar on every
// monitor, the app launcher, the notification daemon with
// its popups and center (replaces dunst) and the OSD for the volume and
// brightness keys (replaces SwayOSD).
//
//   SUPER+D / toggle.sh launcher       show/hide the launcher
//   toggle.sh notifications            open/close the notification center
//   ipc.sh notifications dnd|clear     do not disturb / clear all from scripts
//   hl.dsp.event("quickshell-osd volume +5")    keybinds.lua: volume +/-N,
//                                      mute, mic-mute, brightness +/-N,
//                                      lock caps|num
ShellRoot {
    // No live reload: reloading while it holds the notification service and
    // the tray made the next exit hang. Apply changes with
    // `toggle.sh daemon --restart`.
    settings.watchFiles: false

    NotificationStore {
        id: notificationStore
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

    Launcher {}

    NetworkStatus {
        id: networkStatus
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
