import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets

// The bar at the bottom of a monitor (replaces waybar), part of daemon.qml:
// workspaces and window title on the left, the clock in the middle, tray,
// privacy, sound, battery, network, notifications and power on the right.
// Each module is a chip in its own accent colour; clicks open the menus.
PanelWindow {
    id: bar

    required property var store // NotificationStore
    required property var center // NotificationCenter
    required property var network // NetworkStatus

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
    implicitHeight: 27
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

        Workspaces {
            monitor: bar.monitor
        }

        Label {
            Layout.maximumWidth: 700
            Layout.leftMargin: 4
            visible: !!text
            text: Hyprland.activeToplevel?.title ?? ""
            color: Theme.subtext0
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
                    implicitSize: 15
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

        // Privacy: something records the microphone or the screen
        Row {
            readonly property var inputs: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink).map(n => n.properties["media.class"] ?? "")

            visible: inputs.length > 0
            spacing: 6

            Label {
                visible: parent.inputs.some(c => c.includes("Video"))
                text: Theme.glyph(0xf0379) // 󰍹
                color: Theme.peach
            }
            Label {
                visible: parent.inputs.some(c => c.includes("Audio"))
                text: Theme.glyph(0xf036c) // 󰍬
                color: Theme.peach
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

        // Battery (laptops)
        BarChip {
            readonly property var battery: UPower.displayDevice
            readonly property real percent: battery ? (battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 0
            readonly property bool charging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged || battery?.state === UPowerDeviceState.PendingCharge

            visible: !!battery && battery.isLaptopBattery
            accent: charging ? Theme.teal : percent <= 15 ? Theme.red : percent <= 30 ? Theme.yellow : Theme.green
            text: `${Theme.glyph([0xf244, 0xf243, 0xf242, 0xf241, 0xf240][Math.min(4, Math.round(percent / 25))])}  ${Math.round(percent)}%`
        }

        // Network
        BarChip {
            readonly property string kind: bar.network?.kind ?? ""

            accent: kind ? Theme.sapphire : Theme.red
            text: kind === "wifi" ? `${Theme.glyph(0xf1eb)}  ${bar.network.name}` : kind === "ethernet" ? `${Theme.glyph(0xf0e8)}  Connected` : "⚠ Disconnected"
            onClicked: bar.menu("network")
        }

        // Notifications: solid with a red dot while there are some; click for
        // the center, right click for do not disturb, middle click to clear
        BarChip {
            id: bell

            readonly property int count: bar.store?.entries.length ?? 0
            readonly property bool dnd: bar.store?.dnd ?? false
            property int seen: count

            solid: !dnd && count > 0
            plain: dnd || count === 0
            accent: dnd ? Theme.overlay0 : count > 0 ? Theme.lavender : Theme.overlay2
            onClicked: button => {
                if (button === Qt.RightButton)
                    bar.store.setDnd(!dnd);
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

                Label {
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
            Label {
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
