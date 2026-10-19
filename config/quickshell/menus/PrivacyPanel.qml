import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// The apps behind the bar's privacy chip, part of daemon.qml: which ones use
// the camera, record the microphone or share the screen, with their icon and
// PID like the sound menu's applications. Clicking the icon goes to the app's
// window, the button next to the PID copies it (to end the process by hand:
// deliberately no button for that). Closes by itself once nothing is in use
// anymore.
Popup {
    id: popup

    required property var privacy // Privacy

    name: "privacy"
    cardWidth: 320
    resident: true

    readonly property var sections: [
        { active: privacy.camera, glyph: Theme.glyph(0xf05a0), title: "Camera", apps: privacy.cameraUsers }, // 󰖠
        { active: privacy.microphone, glyph: Theme.glyph(0xf036c), title: "Microphone", apps: privacy.microphoneUsers }, // 󰍬
        { active: privacy.screen, glyph: Theme.glyph(0xf0379), title: "Screen sharing", apps: privacy.screenUsers } // 󰍹
    ]

    function focus(window) {
        const address = window.address.startsWith("0x") ? window.address : `0x${window.address}`;
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
        popup.close();
    }

    Connections {
        target: popup.privacy

        function onActiveChanged() {
            if (!popup.privacy.active && popup.shown)
                popup.close();
        }
    }

    Header {
        glyph: Theme.glyph(0xf0565) // 󰕥
        accent: Theme.peach
        title: "Privacy"
    }

    Repeater {
        model: popup.sections.filter(s => s.active)

        delegate: ColumnLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                spacing: 8

                Label {
                    text: modelData.glyph
                    color: Theme.peach
                    font.pixelSize: 14
                }
                SectionTitle {
                    text: modelData.title
                }
            }

            Label {
                visible: modelData.apps.length === 0
                text: "Unknown app"
                color: Theme.overlay0
                font.italic: true
            }

            Repeater {
                model: modelData.apps

                // [icon]  name  PID [copy]
                delegate: RowLayout {
                    id: user

                    required property var modelData
                    property bool copied: false

                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 8
                        color: Theme.alpha(Theme.peach, iconMouse.containsMouse ? 0.25 : 0.15)

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Label {
                            anchors.centerIn: parent
                            visible: !modelData.icon
                            text: Theme.glyph(0xf08c6) // 󰣆
                            font.pixelSize: 16
                            color: Theme.peach
                        }

                        IconImage {
                            anchors.centerIn: parent
                            visible: !!modelData.icon
                            source: modelData.icon
                            implicitSize: 20
                        }

                        MouseArea {
                            id: iconMouse
                            anchors.fill: parent
                            enabled: !!user.modelData.window
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.focus(user.modelData.window)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.name
                    }
                    Label {
                        visible: modelData.pid > 0
                        text: `PID ${modelData.pid}`
                        color: Theme.overlay1
                        font.pixelSize: 11
                    }
                    IconButton {
                        visible: modelData.pid > 0
                        glyph: Theme.glyph(user.copied ? 0xf012c : 0xf018f) // 󰄬 / 󰆏
                        accent: Theme.green
                        active: user.copied
                        onClicked: {
                            Quickshell.execDetached(["wl-copy", "--", String(user.modelData.pid)]);
                            user.copied = true;
                            copiedReset.restart();
                        }

                        Timer {
                            id: copiedReset
                            interval: 1500
                            onTriggered: user.copied = false
                        }
                    }
                }
            }
        }
    }
}
