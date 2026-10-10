import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Sound popup for the waybar pulseaudio module. Opened by toggle.sh; closes on
// Escape, on clicking outside, or by clicking the bar module again.
ShellRoot {
    PwObjectTracker {
        objects: [...Audio.sinks, ...Audio.sources, ...Audio.streams]
    }

    PanelWindow {
        id: panel

        anchors {
            bottom: true
            right: true
        }
        margins {
            bottom: 6
            right: 6
        }

        implicitWidth: 380
        implicitHeight: card.implicitHeight
        color: "transparent"
        exclusiveZone: 0

        WlrLayershell.namespace: "quickshell-audio"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        HyprlandFocusGrab {
            active: true
            windows: [panel]
            // Clicking the bar icon clears the grab before waybar runs toggle.sh;
            // the stamp tells toggle.sh not to reopen us right away.
            onCleared: {
                Quickshell.execDetached(["touch", `${Quickshell.env("XDG_RUNTIME_DIR")}/qs-audio-closed`]);
                Qt.quit();
            }
        }

        Rectangle {
            id: card

            width: parent.width
            implicitHeight: content.implicitHeight + 32
            radius: 12
            color: Theme.base
            border.width: 1
            border.color: Theme.surface0

            focus: true
            Keys.onEscapePressed: Qt.quit()

            // Slide up out of the bar
            opacity: 0
            transform: Translate { id: slide; y: 12 }
            Component.onCompleted: intro.start()
            ParallelAnimation {
                id: intro
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: slide; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                id: content

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                }
                spacing: 16

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: Audio.glyph(0xf057e) // 󰕾
                        color: Theme.blue
                        font.pixelSize: 16
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "Sound"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    // Full mixer for everything this popup doesn't cover
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 8
                        color: mixerMouse.containsMouse ? Theme.surface1 : Theme.surface0

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Label {
                            anchors.centerIn: parent
                            text: Audio.glyph(0xf0493) // 󰒓
                            color: mixerMouse.containsMouse ? Theme.text : Theme.overlay2
                        }

                        MouseArea {
                            id: mixerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["pavucontrol"]);
                                Qt.quit();
                            }
                        }
                    }
                }

                DeviceSection {
                    Layout.fillWidth: true
                    title: "Output"
                    output: true
                    accent: Theme.blue
                }

                DeviceSection {
                    Layout.fillWidth: true
                    title: "Input"
                    output: false
                    accent: Theme.mauve
                }

                // Per-application volume
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    SectionTitle {
                        text: "Applications"
                    }

                    Label {
                        visible: Audio.streams.length === 0
                        text: "Nothing is playing"
                        color: Theme.overlay0
                        font.italic: true
                    }

                    Repeater {
                        model: Audio.streams

                        delegate: VolumeRow {
                            required property PwNode modelData

                            Layout.fillWidth: true
                            node: modelData
                            accent: Theme.lavender
                            iconSource: Audio.appIcon(modelData)
                            glyph: Audio.glyph(0xf075a) // 󰝚
                            title: Audio.appName(modelData)
                            subtitle: Audio.mediaName(modelData)
                        }
                    }
                }
            }
        }
    }
}
