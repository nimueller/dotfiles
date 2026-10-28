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
// the distro logo (system menu), waiting updates, workspaces and window title on the left, the clock in the middle, tray,
// privacy, sound, battery, Bluetooth, phone, network, notifications and power on the right.
// Each module is a chip in its own accent colour; clicks open the menus.
// In touch mode (Modes.qml) it's taller, and has buttons for what's
// otherwise a key: the launcher, closing the window and the on-screen
// keyboard; in tablet mode it's taller still, and holding a finger on a
// chip is a right click (BarChip.qml). On narrow screens (Modes.compactBar) Bluetooth, the keyboard
// and power are in the system menu instead. The clock moves left of the
// middle when the right side would reach it.
PanelWindow {
    id: bar

    required property var store // NotificationStore
    required property var center // NotificationCenter
    required property var network // NetworkStatus
    required property var privacy // Privacy
    required property var privacyPanel // PrivacyPanel
    required property var phones // PhoneStatus

    readonly property string toggle: Quickshell.shellPath("toggle.sh")
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool compact: Modes.compactBar(screen)

    // The menus right here in the daemon (Menus.qml), the launcher through
    // toggle.sh
    function menu(name) {
        if (Menus.names.includes(name))
            Menus.toggle(name);
        else
            Quickshell.execDetached([toggle, name]);
    }

    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Modes.barSize(27, 40, 48)
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
        id: left

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

        // Waiting updates (Updates.qml), or a dotfiles checkout whose
        // flake.lock is weeks old; the system menu has the details
        BarChip {
            visible: Updates.total > 0 || Updates.flakeStale
            accent: Theme.peach
            text: `${Theme.glyph(0xf06b0)}  ${Updates.total > 0 ? Updates.total : "flake.lock"}` // 󰚰
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
        // Centred, unless the right side reaches it
        x: Math.max(left.x + left.width + 6, Math.min((bar.width - width) / 2, right.x - 6 - width))
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        padding: 14
        accent: Theme.mauve
        bold: true
        text: `${Theme.glyph(0xf073)}  ${Qt.formatDateTime(clock.date, "yyyy-MM-dd")}    ${Theme.glyph(0xf017)}  ${Qt.formatDateTime(clock.date, "HH:mm")}`
        onClicked: bar.menu("calendar")
    }

    // Right: tray and status -----------------------------------------------------
    RowLayout {
        id: right

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        spacing: 6

        // Tray: left click activates, right click (or holding a finger on
        // it) opens the app's menu
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
                    implicitSize: Modes.barSize(15, 20, 24)
                    source: modelData.icon

                    MouseArea {
                        anchors.fill: parent
                        // Touch: over the gaps between the icons and up to
                        // the bar's edges
                        anchors.margins: Modes.touch ? -3 : 0
                        anchors.topMargin: Modes.touch ? -10 : 0
                        anchors.bottomMargin: Modes.touch ? -10 : 0
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
                        onPressAndHold: {
                            if (Modes.touch && trayIcon.modelData.hasMenu)
                                trayMenu.open(trayIcon.modelData, trayIcon);
                        }
                        onWheel: event => trayIcon.modelData.scroll(event.angleDelta.y, false)
                    }
                }
            }
        }

        // Privacy: something records the microphone, uses a camera or shares
        // the screen; click for the apps that do
        BarChip {
            id: privacy

            visible: bar.privacy?.active ?? false
            solid: true
            accent: Theme.peach
            onClicked: bar.privacyPanel.toggle()

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
                    Audio.setMuted(sink, !muted);
                else
                    bar.menu("audio");
            }
            onScrolled: steps => {
                Audio.setVolume(sink, Math.round((volume + steps * 0.02) * 100) / 100);
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

            visible: (!!adapter || hardware) && !bar.compact
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

        // Touch: the on-screen keyboard (osk.sh)
        BarChip {
            visible: Modes.touch && !bar.compact
            plain: true
            accent: Theme.text
            text: Theme.glyph(0xf030c) // 󰌌
            onClicked: Quickshell.execDetached([Quickshell.shellPath("osk.sh")])
        }

        // Power menu
        BarChip {
            id: power

            visible: !bar.compact
            accent: hovered ? Theme.red : Theme.overlay1
            plain: !hovered
            text: Theme.glyph(0xf0425) // 󰐥
            onClicked: bar.menu("power")
        }
    }
}
