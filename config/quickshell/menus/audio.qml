import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Sound menu for the waybar pulseaudio module
Popup {
    name: "audio"

    PwObjectTracker {
        objects: [...Audio.sinks, ...Audio.sources, ...Audio.streams]
    }

    Header {
        glyph: Theme.glyph(0xf057e) // 󰕾
        accent: Theme.blue
        title: "Sound"

        // Full mixer for everything this menu doesn't cover
        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            onClicked: {
                Quickshell.execDetached(["pavucontrol"]);
                Qt.quit();
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
                glyph: Theme.glyph(0xf075a) // 󰝚
                title: Audio.appName(modelData)
                subtitle: Audio.mediaName(modelData)
            }
        }
    }
}
