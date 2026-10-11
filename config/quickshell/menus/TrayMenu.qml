import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// The menu of a tray icon, drawn in the theme (Qt's native menus would need
// QApplication and look out of place). Opens above the icon; submenus open
// in place with a "Back" row. Closes on a click outside or Escape.
PopupWindow {
    id: root

    property var item: null // SystemTrayItem
    property var stack: [] // submenus opened, innermost last
    readonly property var menu: stack.length ? stack[stack.length - 1] : item?.menu ?? null

    function open(trayItem, icon) {
        item = trayItem;
        stack = [];
        anchor.item = icon;
        visible = true;
    }

    function close() {
        visible = false;
        item = null;
        stack = [];
    }

    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.margins.top: -8
    implicitWidth: 240
    implicitHeight: card.implicitHeight
    color: "transparent"

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: root.close()
    }

    QsMenuOpener {
        id: opener
        menu: root.menu
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: column.implicitHeight + 12
        radius: 10
        color: Theme.base
        border.width: 1
        border.color: Theme.surface0

        focus: true
        Keys.onEscapePressed: root.close()

        ColumnLayout {
            id: column

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 6
            }
            spacing: 0

            // Back out of a submenu
            MenuRow {
                visible: root.stack.length > 0
                glyph: Theme.glyph(0xf0141) // 󰅁
                text: "Back"
                onTriggered: root.stack = root.stack.slice(0, -1)
            }

            Repeater {
                model: opener.children

                delegate: Item {
                    id: entryItem

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: modelData.isSeparator ? 9 : row.implicitHeight

                    Rectangle {
                        visible: entryItem.modelData.isSeparator
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: 1
                        color: Theme.surface0
                    }

                    MenuRow {
                        id: row

                        visible: !entryItem.modelData.isSeparator
                        width: parent.width
                        text: entryItem.modelData.text
                        icon: entryItem.modelData.icon
                        active: entryItem.modelData.enabled
                        submenu: entryItem.modelData.hasChildren
                        // Check boxes and radio buttons
                        glyph: entryItem.modelData.buttonType === QsMenuButtonType.None ? "" : entryItem.modelData.checkState === Qt.Checked ? Theme.glyph(entryItem.modelData.buttonType === QsMenuButtonType.RadioButton ? 0xf043e : 0xf0132) : Theme.glyph(entryItem.modelData.buttonType === QsMenuButtonType.RadioButton ? 0xf043d : 0xf0131) // 󰐾 󰄲 / 󰐽 󰄱
                        onTriggered: {
                            if (entryItem.modelData.hasChildren) {
                                root.stack = [...root.stack, entryItem.modelData];
                            } else {
                                entryItem.modelData.triggered();
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }

    // One clickable row of the menu
    component MenuRow: Rectangle {
        id: menuRow

        property string text: ""
        property string icon: ""
        property string glyph: ""
        property bool submenu: false
        property bool active: true // the app may disable entries

        signal triggered

        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: rowMouse.containsMouse && active ? Theme.surface0 : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Item {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                visible: !!menuRow.icon || !!menuRow.glyph

                IconImage {
                    anchors.fill: parent
                    visible: !!menuRow.icon && !menuRow.glyph
                    source: menuRow.icon
                }
                Label {
                    anchors.centerIn: parent
                    visible: !!menuRow.glyph
                    text: menuRow.glyph
                    color: menuRow.active ? Theme.lavender : Theme.overlay0
                }
            }
            Label {
                Layout.fillWidth: true
                text: menuRow.text.replace(/&(?!&)/g, "") // drop mnemonic markers
                color: menuRow.active ? (rowMouse.containsMouse ? Theme.text : Theme.subtext1) : Theme.overlay0
            }
            Label {
                visible: menuRow.submenu
                text: Theme.glyph(0xf0142) // 󰅂
                color: Theme.overlay1
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: menuRow.active
            cursorShape: Qt.PointingHandCursor
            onClicked: menuRow.triggered()
        }
    }
}
