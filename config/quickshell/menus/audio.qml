// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Sound menu for the bar's sound module
Popup {
    id: popup

    name: "audio"

    PwObjectTracker {
        objects: Audio.all
    }

    // The PIDs of windows opened since the last refresh, for the apps' names
    Component.onCompleted: Windows.refresh()

    Header {
        glyph: Theme.glyph(0xf057e) // 󰕾
        accent: Theme.blue
        title: I18n.tr("Sound")

        // Full mixer for everything this menu doesn't cover
        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            onClicked: {
                Quickshell.execDetached(["pavucontrol"]);
                popup.close();
            }
        }
    }

    DeviceSection {
        Layout.fillWidth: true
        title: I18n.tr("Output")
        output: true
        accent: Theme.blue
    }

    DeviceSection {
        Layout.fillWidth: true
        title: I18n.tr("Input")
        output: false
        accent: Theme.mauve
    }

    // Media players (MPRIS): cover, title, play/pause/skip, position
    ColumnLayout {
        Layout.fillWidth: true
        visible: Media.players.length > 0
        spacing: 10

        SectionTitle {
            text: I18n.tr("Playing")
        }

        Repeater {
            model: Media.players

            delegate: MediaCard {
                required property var modelData

                Layout.fillWidth: true
                player: modelData
            }
        }
    }

    // Per-application volume
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        SectionTitle {
            text: I18n.tr("Applications")
        }

        Label {
            visible: Audio.streams.length === 0
            text: I18n.tr("Nothing is playing")
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
                subtitle: Audio.streamLabel(modelData)
            }
        }
    }
}
