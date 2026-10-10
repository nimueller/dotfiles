import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Resident part of the desktop shell (started with Hyprland, see
// autostart.lua; also D-Bus activated for notifications): the notification
// daemon with its popups and center (replaces dunst) and the OSD for the
// volume and brightness keys (replaces SwayOSD).
//
//   toggle.sh notifications            open/close the notification center
//   ipc.sh notifications dnd|clear     waybar's right/middle click on the bell
//   hl.dsp.event("quickshell-osd volume +5")    keybinds.lua: volume +/-N,
//                                      mute, mic-mute, brightness +/-N
ShellRoot {
    NotificationStore {
        id: store
    }

    NotificationPopups {
        store: store
    }

    NotificationCenter {
        id: center
        store: store
    }

    Osd {
        id: osd
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            center.toggle();
        }
        function dnd(): void {
            store.setDnd(!store.dnd);
        }
        function clear(): void {
            store.clear();
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
        }
    }
}
