import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Notifications popping up at the top right of the main monitor (set in
// Machine Settings, else the first screen), newest on top.
PanelWindow {
    id: root

    required property var store
    readonly property var shown: store.popups.slice(0, 6).map(key => store.entry(key)).filter(e => e)

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
            model: root.shown

            delegate: NotificationToast {
                required property var modelData

                Layout.fillWidth: true
                entry: modelData
                onActivated: root.store.activate(modelData.key)
                onClosed: root.store.closePopup(modelData.key)
                onCloseAll: root.store.closeAllPopups()
                onAction: identifier => root.store.invoke(modelData.key, identifier)
            }
        }
    }
}
