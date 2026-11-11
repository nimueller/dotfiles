// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell

// What can go from the disk, from the system menu: the trash and what comes
// back by itself (Cleanup.qml, cleanup.py), each with its size and a button.
// None of it can be undone, so a button asks once more before it clears.
Popup {
    id: root

    name: "cleanup"
    atLeft: true
    cardWidth: 420

    readonly property var ready: Cleanup.items.filter(item => !item.blocked)
    readonly property real total: ready.reduce((sum, item) => sum + item.bytes, 0)
    property string confirming: "" // id or "all", until the timer runs out

    Component.onCompleted: Cleanup.refresh()

    function ask(key, clear) {
        if (confirming === key) {
            confirming = "";
            clear();
        } else {
            confirming = key;
            confirmTimer.restart();
        }
    }

    Timer {
        id: confirmTimer

        interval: 4000
        onTriggered: root.confirming = ""
    }

    Header {
        glyph: Theme.glyph(0xf00e2) // 󰃢
        title: I18n.tr("Clean up")
        badge: Cleanup.scanned ? I18n.tr("%1 free", Cleanup.size(Cleanup.free)) : ""
    }

    Label {
        Layout.fillWidth: true
        visible: !Cleanup.items.length
        text: Cleanup.scanned ? I18n.tr("Nothing to clean up") : I18n.tr("Looking at the disk…")
        color: Theme.subtext0
    }

    Column {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: Cleanup.items

            delegate: RowLayout {
                id: entry

                required property var modelData
                readonly property bool cleaning: Cleanup.cleaning === modelData.id

                width: parent.width
                spacing: 8

                Column {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    spacing: 2

                    Label {
                        width: parent.width
                        text: `${entry.modelData.title} · ${Cleanup.size(entry.modelData.bytes)}`
                        font.bold: true
                    }
                    Label {
                        width: parent.width
                        text: entry.modelData.blocked || entry.modelData.detail
                        color: entry.modelData.blocked ? Theme.peach : Theme.overlay1
                        font.pixelSize: 11
                    }
                }
                IconButton {
                    visible: !entry.modelData.blocked
                    text: {
                        if (entry.cleaning) {
                            return I18n.tr("Clearing…");
                        }
                        if (root.confirming === entry.modelData.id) {
                            return I18n.tr("Sure?");
                        }
                        return I18n.tr("Clear");
                    }
                    accent: Theme.red
                    active: entry.cleaning || root.confirming === entry.modelData.id
                    onClicked: if (!Cleanup.busy) {
                        root.ask(entry.modelData.id, () => Cleanup.clean([entry.modelData.id]));
                    }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !!Cleanup.error
        text: Cleanup.error
        color: Theme.red
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6

        Item {
            Layout.fillWidth: true
        }
        IconButton {
            text: I18n.tr("Close")
            onClicked: root.close()
        }
        IconButton {
            visible: root.ready.length > 1
            glyph: Theme.glyph(0xf00e2) // 󰃢
            text: root.confirming === "all" ? I18n.tr("Sure?") : I18n.tr("Clear all · %1", Cleanup.size(root.total))
            accent: Theme.red
            active: true
            onClicked: if (!Cleanup.busy) {
                root.ask("all", () => Cleanup.clean(root.ready.map(item => item.id)));
            }
        }
    }
}
