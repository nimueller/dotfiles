import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Notifications popping up at the top right of the main monitor (set in
// Machine Settings, else the first screen), newest on top.
PanelWindow {
    id: root

    required property var store
    // Keys only, as in NotificationCenter.qml: a copied entry would keep a
    // dangling pointer to its notification once that is gone
    readonly property var shown: store.popups.slice(0, 6).filter(key => store.entry(key))

    screen: LocalSettings.mainScreen
    anchors {
        top: true
        right: true
    }
    margins {
        top: 16
        right: 16
    }
    implicitWidth: 380
    implicitHeight: Math.max(1, column.implicitHeight)
    visible: shown.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell-notification-popups"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    ColumnLayout {
        id: column

        width: parent.width
        spacing: 8

        Repeater {
            // A ScriptModel keeps the toasts that stay when the list changes;
            // with the plain array every change rebuilt all of them, which
            // restarted their countdowns (and could undo one that had run out)
            model: ScriptModel {
                values: root.shown
            }

            delegate: NotificationToast {
                required property int modelData

                Layout.fillWidth: true
                entry: root.store.entry(modelData) ?? {}
                onActivated: root.store.activate(modelData)
                onClosed: root.store.closePopup(modelData)
                onCloseAll: root.store.closeAllPopups()
                onAction: identifier => root.store.invoke(modelData, identifier)
            }
        }
    }
}
