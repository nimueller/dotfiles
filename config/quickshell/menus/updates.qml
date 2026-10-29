// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell

// Arch news since the last full upgrade (Updates.news), before updating:
// opened by the bar's red update chip and by the system menu's Update
// button while there are any. The news often ask for a manual step before
// or after the upgrade, so reading them is the main button; a click on one
// opens it in the browser. Updating anyway is there, but quiet.
Popup {
    id: root

    name: "updates"
    atLeft: true
    cardWidth: 420

    // Fresh ones while it's open, as in the system menu
    Component.onCompleted: Updates.refresh()

    function open(links) {
        for (const link of links)
            Quickshell.execDetached(["xdg-open", link]);
        root.close();
    }

    Header {
        glyph: Theme.glyph(0xf0395) // 󰎕
        accent: Theme.red
        title: "Arch news"
        badge: Updates.news.length > 1 ? String(Updates.news.length) : ""
    }

    Label {
        Layout.fillWidth: true
        text: `Published since the last upgrade${Updates.lastUpgrade !== null ? ` (${Updates.lastUpgrade === 0 ? "today" : `${Updates.lastUpgrade} ${Updates.lastUpgrade === 1 ? "day" : "days"} ago`})` : ""}. Read them before updating: some need a step of their own.`
        color: Theme.subtext0
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }

    Column {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: Updates.news

            delegate: Rectangle {
                id: entry

                required property var modelData

                width: parent.width
                implicitHeight: column.implicitHeight + 12
                radius: 6
                color: mouse.containsMouse ? Theme.surface0 : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }

                Column {
                    id: column

                    x: 8
                    y: 6
                    width: parent.width - 16
                    spacing: 2

                    Label {
                        width: parent.width
                        text: entry.modelData.title
                        font.bold: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                    Label {
                        text: `${entry.modelData.date} · archlinux.org`
                        color: Theme.overlay1
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.open([entry.modelData.link])
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6

        IconButton {
            glyph: Theme.glyph(0xf06b0) // 󰚰
            text: "Update anyway"
            onClicked: {
                Updates.update();
                root.close();
            }
        }
        Item {
            Layout.fillWidth: true
        }
        IconButton {
            text: "Cancel"
            onClicked: root.close()
        }
        IconButton {
            glyph: Theme.glyph(0xf0395) // 󰎕
            text: Updates.news.length > 1 ? "Read the news" : "Read it"
            accent: Theme.red
            active: true
            onClicked: root.open(Updates.news.map(n => n.link))
        }
    }
}
