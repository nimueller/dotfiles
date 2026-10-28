import QtQuick
import QtQuick.Controls as Controls

// Drop-down list in the theme. `model` is a list of strings or of
// { text, value } objects; picked(value) reports a choice.
Controls.ComboBox {
    id: root

    property var current: null // the value shown as chosen
    readonly property var entries: (model ?? []).map(e => typeof e === "object" ? e : { text: String(e), value: e })

    signal picked(var value)

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    model: []
    textRole: "text"
    currentIndex: entries.findIndex(e => same(e.value, current))
    implicitHeight: 28
    onActivated: index => root.picked(entries[index].value)

    background: Rectangle {
        radius: 8
        color: Theme.mantle
        border.width: 1
        border.color: root.popup.visible || root.hovered ? Theme.sapphire : Theme.surface1
    }

    contentItem: Label {
        leftPadding: 10
        rightPadding: 24
        text: root.currentIndex >= 0 ? root.entries[root.currentIndex]?.text ?? "—" : "—"
    }

    indicator: Label {
        x: root.width - width - 10
        anchors.verticalCenter: parent.verticalCenter
        text: Theme.glyph(0xf0140) // 󰅀
        color: Theme.overlay1
    }

    delegate: Controls.ItemDelegate {
        id: entry

        required property var modelData
        required property int index

        width: root.popup.width - 8
        height: 26
        highlighted: root.highlightedIndex === index

        background: Rectangle {
            radius: 6
            color: entry.highlighted ? Theme.surface0 : "transparent"
        }
        contentItem: Label {
            text: root.entries[entry.index]?.text ?? ""
            color: entry.index === root.currentIndex ? Theme.sapphire : Theme.text
        }
    }

    popup: Controls.Popup {
        y: root.height + 4
        width: root.width
        implicitHeight: Math.min(list.contentHeight + 8, 260)
        padding: 4

        background: Rectangle {
            radius: 8
            color: Theme.base
            border.width: 1
            border.color: Theme.surface0
        }

        contentItem: ListView {
            id: list

            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
        }
    }
}
