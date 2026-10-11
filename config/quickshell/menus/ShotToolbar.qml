import QtQuick
import QtQuick.Layouts

// Toolbar of the screenshot editor (ShotScreen.qml): drawing tools, colour,
// stroke size, undo / redo, resolution, then copy, save and cancel. Hovering a button names it and its key underneath.
Rectangle {
    id: bar

    required property var editor
    required property int outWidth
    required property int outHeight
    property string hint: ""

    readonly property var tools: [
        { id: "select", glyph: 0xf01be, name: "Move and resize the selection", key: "V" },
        { id: "pen", glyph: 0xf03eb, name: "Pen", key: "P" },
        { id: "line", glyph: 0xf0fdf, name: "Line", key: "L" },
        { id: "arrow", glyph: 0xf005c, name: "Arrow", key: "A" },
        { id: "rect", glyph: 0xf0763, name: "Rectangle", key: "R" },
        { id: "ellipse", glyph: 0xf0766, name: "Ellipse", key: "O" },
        { id: "marker", glyph: 0xf0652, name: "Highlighter", key: "M" },
        { id: "text", glyph: 0xf0284, name: "Text", key: "T" },
        { id: "pixelate", glyph: 0xf00b5, name: "Pixelate", key: "B" }
    ]

    function say(hovered, text) {
        if (hovered)
            hint = text;
        else if (hint === text)
            hint = "";
    }

    implicitWidth: row.implicitWidth + 16
    implicitHeight: row.implicitHeight + 16
    width: implicitWidth
    height: implicitHeight
    radius: 12
    color: Theme.base
    border.width: 1
    border.color: Theme.surface0

    // Clicks between the buttons stay on the toolbar
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: bar.tools

            delegate: IconButton {
                required property var modelData

                glyph: Theme.glyph(modelData.glyph)
                active: bar.editor.tool === modelData.id
                onClicked: bar.editor.tool = modelData.id
                onHoveredChanged: bar.say(hovered, `${modelData.name}   ${modelData.key}`)
            }
        }

        Separator {}

        Repeater {
            model: bar.editor.colors

            delegate: Rectangle {
                required property var modelData

                readonly property bool current: Qt.colorEqual(bar.editor.color, modelData)

                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                radius: 10
                color: modelData
                border.width: current ? 2 : 1
                border.color: current ? Theme.text : Theme.surface2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.editor.color = parent.modelData
                }
            }
        }

        // Stroke and text size: a dot of that size, click for the next one
        IconButton {
            id: sizeButton

            onClicked: bar.editor.size = (bar.editor.size + 1) % 3
            onHoveredChanged: bar.say(hovered, "Thickness and text size")

            Rectangle {
                anchors.centerIn: parent
                width: [4, 7, 12][bar.editor.size]
                height: width
                radius: width / 2
                color: sizeButton.hovered ? Theme.text : Theme.overlay2
            }
        }

        Separator {}

        IconButton {
            glyph: Theme.glyph(0xf054c) // 󰕌
            opacity: bar.editor.shapes.length ? 1 : 0.4
            onClicked: bar.editor.undo()
            onHoveredChanged: bar.say(hovered, "Undo   Ctrl+Z")
        }
        IconButton {
            glyph: Theme.glyph(0xf044e) // 󰑎
            opacity: bar.editor.undone.length ? 1 : 0.4
            onClicked: bar.editor.redo()
            onHoveredChanged: bar.say(hovered, "Redo   Ctrl+Shift+Z")
        }

        Separator {}

        Repeater {
            model: bar.editor.percents

            delegate: IconButton {
                required property int modelData
                required property int index

                text: `${modelData}%`
                active: bar.editor.percent === modelData
                onClicked: bar.editor.percent = modelData
                onHoveredChanged: bar.say(hovered, `Scale to ${modelData}%   ${index + 1}`)
            }
        }

        Label {
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            text: `${bar.outWidth} × ${bar.outHeight}`
            color: Theme.subtext0
        }

        Separator {}

        IconButton {
            glyph: Theme.glyph(0xf018f) // 󰆏
            text: "Copy"
            accent: Theme.green
            active: true
            onClicked: bar.editor.finish("copy")
            onHoveredChanged: bar.say(hovered, "Copy to the clipboard   Enter")
        }
        IconButton {
            glyph: Theme.glyph(0xf0193) // 󰆓
            text: "Save"
            accent: Theme.blue
            active: true
            onClicked: bar.editor.finish("save")
            onHoveredChanged: bar.say(hovered, "Save to ~/Pictures/Screenshots and copy   Ctrl+S")
        }
        IconButton {
            glyph: Theme.glyph(0xf0156) // 󰅖
            onClicked: bar.editor.cancel()
            onHoveredChanged: bar.say(hovered, "Cancel   Esc")
        }
    }

    // What the hovered button does
    Rectangle {
        visible: !!bar.hint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 6
        width: hintLabel.implicitWidth + 20
        height: 24
        radius: 6
        color: Theme.base
        border.width: 1
        border.color: Theme.surface0

        Label {
            id: hintLabel
            anchors.centerIn: parent
            text: bar.hint
            color: Theme.subtext1
        }
    }

    component Separator: Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 18
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        color: Theme.surface1
    }
}
