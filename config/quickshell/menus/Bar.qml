import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets

// The bar at the bottom of a monitor, part of daemon.qml:
// the distro logo (system menu), workspaces and window title on the left, the clock in the middle, tray,
// privacy, sound, battery, Bluetooth, phone, network, notifications and power on the right.
// Each module is a chip in its own accent colour; clicks open the menus.
// In touch mode (Modes.qml) it's taller, and has buttons for what's
// otherwise a key: the launcher, closing the window and the on-screen
// keyboard.
PanelWindow {
    id: bar

    required property var store // NotificationStore
    required property var center // NotificationCenter
    required property var network // NetworkStatus
    required property var privacy // Privacy
    required property var phones // PhoneStatus

    readonly property string toggle: Quickshell.shellPath("toggle.sh")
    readonly property var monitor: Hyprland.monitorFor(screen)

    function menu(name) {
        Quickshell.execDetached([toggle, name]);
    }

    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Modes.touch ? 40 : 27
    color: Theme.crust

    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.surface0
    }

    // Left: workspaces and the focused window ------------------------------------
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        spacing: 6

        // System menu (system.qml): the system at a glance, Machine Settings
        BarChip {
            accent: Theme.blue
            text: Theme.glyph(0xf303) // 
            onClicked: bar.menu("system")
        }

        // Touch: the launcher, which is SUPER + D otherwise
        BarChip {
            visible: Modes.touch
            accent: Theme.mauve
            text: Theme.glyph(0xf003b) // 󰀻
            onClicked: bar.menu("launcher")
        }

        Workspaces {
            monitor: bar.monitor
        }

        BarLabel {
            Layout.maximumWidth: 700
            Layout.leftMargin: 4
            // Off unless switched on in Machine Settings (LocalSettings.qml)
            visible: LocalSettings.windowTitle && !!text
            text: Hyprland.activeToplevel?.title ?? ""
            color: Theme.subtext0
        }

        // Touch: close the focused window
        BarChip {
            visible: Modes.touch && !!Hyprland.activeToplevel
            plain: true
            accent: Theme.red
            text: Theme.glyph(0xf0156) // 󰅖
            onClicked: Hyprland.dispatch("hl.dsp.window.close()")
        }
    }

    // Middle: clock --------------------------------------------------------------
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    BarChip {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        padding: 14
        accent: Theme.mauve
        bold: true
        text: `${Theme.glyph(0xf073)}  ${Qt.formatDateTime(clock.date, "yyyy-MM-dd")}    ${Theme.glyph(0xf017)}  ${Qt.formatDateTime(clock.date, "HH:mm")}`
        onClicked: bar.menu("calendar")
    }

    // Right: tray and status -----------------------------------------------------
    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        spacing: 6

        // Tray: left click activates, right click opens the app's menu
        TrayMenu {
            id: trayMenu
        }

        BarChip {
            visible: SystemTray.items.values.length > 0
            plain: true
            interactive: false

            Repeater {
                model: SystemTray.items.values

                delegate: IconImage {
                    id: trayIcon

                    required property var modelData

                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Modes.touch ? 20 : 15
                    source: modelData.icon

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: event => {
                            const item = trayIcon.modelData;
                            if (event.button === Qt.MiddleButton)
                                item.secondaryActivate();
                            else if (event.button === Qt.LeftButton && !item.onlyMenu)
                                item.activate();
                            else if (item.hasMenu)
                                trayMenu.open(item, trayIcon);
                        }
                        onWheel: event => trayIcon.modelData.scroll(event.angleDelta.y, false)
                    }
                }
            }
        }

        // Privacy: something records the microphone, uses a camera or shares
        // the screen
        BarChip {
            id: privacy

            visible: bar.privacy?.active ?? false
            solid: true
            accent: Theme.peach
            interactive: false

            BarLabel {
                visible: bar.privacy.camera
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.glyph(0xf05a0) // 󰖠
                color: privacy.foreground
            }
            BarLabel {
                visible: bar.privacy.microphone
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.glyph(0xf036c) // 󰍬
                color: privacy.foreground
            }
            BarLabel {
                visible: bar.privacy.screen
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.glyph(0xf0379) // 󰍹
                color: privacy.foreground
            }
        }

        // Sound: click for the menu, right click for pavucontrol, scroll for the
        // volume, middle click to mute
        BarChip {
            id: sound

            readonly property var sink: Pipewire.defaultAudioSink
            readonly property real volume: sink?.audio?.volume ?? 0
            readonly property bool muted: sink?.audio?.muted ?? false

            accent: muted ? Theme.overlay0 : Theme.blue
            plain: muted
            text: muted ? `${Theme.glyph(0xf466)}  Muted` : `${Theme.glyph([0xf026, 0xf027, 0xf028][Math.min(2, Math.floor(volume * 3))])}  ${Math.round(volume * 100)}%`
            onClicked: button => {
                if (button === Qt.RightButton)
                    Quickshell.execDetached(["pavucontrol"]);
                else if (button === Qt.MiddleButton)
                    sink.audio.muted = !muted;
                else
                    bar.menu("audio");
            }
            onScrolled: steps => {
                if (sink?.audio)
                    sink.audio.volume = Math.max(0, Math.min(1, Math.round((volume + steps * 0.02) * 100) / 100));
            }

            PwObjectTracker {
                objects: [sound.sink]
            }
        }

        // Battery (laptops): click for the battery menu (battery.qml) with
        // the power profiles
        BarChip {
            readonly property var battery: UPower.displayDevice
            readonly property real percent: battery ? (battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 0
            readonly property bool charging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged || battery?.state === UPowerDeviceState.PendingCharge

            visible: !!battery && battery.isLaptopBattery
            accent: charging ? Theme.teal : percent <= 15 ? Theme.red : percent <= 30 ? Theme.yellow : Theme.green
            text: `${Theme.glyph([0xf244, 0xf243, 0xf242, 0xf241, 0xf240][Math.min(4, Math.round(percent / 25))])}  ${Math.round(percent)}%${charging ? ` ${Theme.glyph(0xf0e7)}` : ""}` // 
            onClicked: bar.menu("battery")
        }

        // Bluetooth, where there's an adapter: the connected device (its
        // battery) or how many; click for the menu (bluetooth.qml), right
        // click to switch it on or off. Also where BlueZ doesn't list the
        // controller (bluetoothd not running, no address of its own), with
        // the menu saying why.
        BarChip {
            id: bluetooth

            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property bool on: adapter?.enabled ?? false
            readonly property var connected: (adapter?.devices.values ?? []).filter(d => d.connected)
            readonly property var device: connected.length === 1 ? connected[0] : null
            property bool hardware: false

            visible: !!adapter || hardware
            accent: on ? Theme.blue : Theme.overlay0
            plain: !on
            text: {
                if (!on)
                    return Theme.glyph(0xf00b2); // 󰂲
                if (device)
                    return `${Theme.glyph(0xf00b1)}  ${device.name.length > 14 ? device.name.slice(0, 13) + "…" : device.name}${device.batteryAvailable ? ` ${Math.round(device.battery * 100)}%` : ""}`; // 󰂱
                return connected.length ? `${Theme.glyph(0xf00b1)}  ${connected.length}` : Theme.glyph(0xf00af); // 󰂯
            }
            onClicked: button => {
                if (button === Qt.RightButton && adapter)
                    adapter.enabled = !on;
                else
                    bar.menu("bluetooth");
            }

            Process {
                running: true
                command: ["sh", "-c", "ls -A /sys/class/bluetooth"]
                stdout: StdioCollector {
                    onStreamFinished: bluetooth.hardware = !!text.trim()
                }
            }
        }

        // Phone (KDE Connect): its battery while it's connected; click for the
        // menu (kdeconnect.qml), right click to send files
        BarChip {
            readonly property var phone: bar.phones?.reachable[0] ?? null
            readonly property int charge: phone?.battery ?? -1

            visible: !!phone
            accent: phone?.charging ? Theme.teal : charge >= 0 && charge <= 15 ? Theme.red : Theme.green
            text: charge >= 0 ? `${Theme.glyph(0xf011c)}  ${charge}%${phone.charging ? ` ${Theme.glyph(0xf0e7)}` : ""}` : Theme.glyph(0xf011c) // 󰄜 
            onClicked: button => {
                if (button === Qt.RightButton)
                    bar.phones.run("send", phone);
                else
                    bar.menu("kdeconnect");
            }
        }

        // Network: Wi-Fi with its signal and the network's name (shortened)
        BarChip {
            readonly property string kind: bar.network?.kind ?? ""
            readonly property string name: bar.network?.name ?? ""
            readonly property int signal: bar.network?.signal ?? 100

            accent: kind ? Theme.sapphire : Theme.red
            text: kind === "wifi" ? `${Theme.glyph(signal > 75 ? 0xf0928 : signal > 50 ? 0xf0925 : signal > 25 ? 0xf0922 : 0xf091f)}  ${name.length > 18 ? name.slice(0, 17) + "…" : name}` : kind === "ethernet" ? `${Theme.glyph(0xf0e8)}  Connected` : "⚠ Disconnected" // 󰤨 󰤥 󰤢 󰤟
            onClicked: bar.menu("network")
        }

        // Notifications: solid with a red dot while there are some; click for
        // the center, right click for do not disturb, middle click to clear
        BarChip {
            id: bell

            readonly property int count: bar.store?.history.length ?? 0
            readonly property bool dnd: bar.store?.silenced ?? false // or the screen is shared
            property int seen: count

            solid: !dnd && count > 0
            plain: dnd || count === 0
            accent: dnd ? Theme.overlay0 : count > 0 ? Theme.lavender : Theme.overlay2
            onClicked: button => {
                if (button === Qt.RightButton)
                    bar.store.setDnd(!bar.store.dnd);
                else if (button === Qt.MiddleButton)
                    bar.store.clear();
                else
                    bar.center.toggle();
            }

            // A short pulse when new notifications arrive
            onCountChanged: {
                if (count > seen && !dnd)
                    pulse.restart();
                seen = count;
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14

                BarLabel {
                    anchors.centerIn: parent
                    text: Theme.glyph(bell.dnd ? 0xf009b : 0xf009a) // 󰂛 / 󰂚
                    color: bell.foreground
                }
                Rectangle {
                    visible: bell.solid
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -1
                    anchors.rightMargin: -2
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "#e64553" // Catppuccin Latte red: Macchiato's is too pale on lavender
                }
            }
            BarLabel {
                visible: bell.solid
                anchors.verticalCenter: parent.verticalCenter
                text: bell.count
                font.bold: true
                color: bell.foreground
            }

            Rectangle {
                id: ring

                parent: bell
                anchors.centerIn: parent
                width: bell.width
                height: bell.height
                radius: bell.radius
                color: "transparent"
                border.width: 2
                border.color: Theme.lavender
                opacity: 0
            }
            SequentialAnimation {
                id: pulse
                loops: 3
                ParallelAnimation {
                    NumberAnimation { target: ring; property: "opacity"; from: 0.8; to: 0; duration: 1200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.3; duration: 1200; easing.type: Easing.OutCubic }
                }
            }
        }

        // Touch: the on-screen keyboard (squeekboard, started by modes.lua),
        // which otherwise only shows for a focused text field
        BarChip {
            visible: Modes.touch
            plain: true
            accent: Theme.text
            text: Theme.glyph(0xf030c) // 󰌌
            onClicked: Quickshell.execDetached(["sh", "-c", `
                pidof squeekboard >/dev/null || { squeekboard >/dev/null 2>&1 & sleep 1; }
                osk="sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0"
                if [ "$(busctl --user get-property $osk Visible)" = "b true" ]; then show=false; else show=true; fi
                busctl --user call $osk SetVisible b $show
            `])
        }

        // Power menu
        BarChip {
            id: power

            accent: hovered ? Theme.red : Theme.overlay1
            plain: !hovered
            text: Theme.glyph(0xf0425) // 󰐥
            onClicked: bar.menu("power")
        }
    }
}
