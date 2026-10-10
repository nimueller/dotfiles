import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Notification center for the waybar bell. dunst still shows the popups; this
// lists and manages its history (missed / timed-out notifications).
Popup {
    id: popup

    name: "notifications"
    cardWidth: 400

    property var entries: []
    property bool paused: false
    property real now: 0 // seconds since boot, same clock as dunst's timestamps
    property bool loaded: false

    readonly property string script: `${Quickshell.env("HOME")}/.config/waybar/scripts/notifications.sh`

    function refresh() {
        history.running = true;
    }

    // Run a dunstctl command, then refresh this list and the bar's bell
    function act(command) {
        action.command = ["sh", "-c", `${command}; pkill -RTMIN+8 waybar`];
        action.running = true;
    }

    function clean(text) {
        return (text ?? "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'").replace(/\s+/g, " ").trim();
    }

    Process {
        id: history
        running: true
        command: ["sh", "-c", "cut -d' ' -f1 /proc/uptime; dunstctl is-paused; dunstctl history"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [uptime, paused, ...json] = text.split("\n");
                popup.now = parseFloat(uptime);
                popup.paused = paused.trim() === "true";
                try {
                    popup.entries = JSON.parse(json.join("\n")).data[0].map(n => ({
                        id: n.id.data,
                        app: popup.clean(n.appname.data),
                        summary: popup.clean(n.summary.data),
                        body: popup.clean(n.body.data),
                        icon: n.icon_path.data,
                        urgency: n.urgency.data,
                        time: n.timestamp.data / 1e6
                    }));
                } catch (e) {
                    popup.entries = [];
                }
                popup.loaded = true;
            }
        }
    }

    Process {
        id: action
        onExited: popup.refresh()
    }

    // Focus the sending app; close if that worked, otherwise the script shows
    // the notification again and we stay open.
    Process {
        id: opener
        onExited: code => {
            if (code === 0)
                popup.close();
        }
    }

    // Pick up new notifications and keep the ages fresh while open
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: popup.refresh()
    }

    Header {
        glyph: Theme.glyph(popup.paused ? 0xf009b : 0xf009a) // 󰂛 / 󰂚
        accent: popup.paused ? Theme.overlay1 : Theme.lavender
        title: "Notifications"
        badge: popup.entries.length || ""

        IconButton {
            glyph: Theme.glyph(0xf009b) // 󰂛
            text: popup.paused ? "Silenced" : "Silence"
            accent: Theme.peach
            active: popup.paused
            onClicked: popup.act("dunstctl set-paused toggle")
        }
        IconButton {
            visible: popup.entries.length > 0
            glyph: Theme.glyph(0xf05e9) // 󰗩
            text: "Clear"
            onClicked: popup.act("dunstctl history-clear")
        }
    }

    // Do-not-disturb banner
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        visible: popup.paused
        radius: 8
        color: Theme.alpha(Theme.peach, 0.12)

        Label {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            text: "Do not disturb is on, new notifications are held back"
            font.pixelSize: 11
            color: Theme.peach
        }
    }

    // Empty state
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        visible: popup.loaded && popup.entries.length === 0
        spacing: 6

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: Theme.glyph(0xf009c) // 󰂜
            font.pixelSize: 32
            color: Theme.surface2
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "You're all caught up"
            color: Theme.overlay1
        }
    }

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 480)
        visible: popup.entries.length > 0
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: popup.entries

        delegate: NotificationCard {
            required property var modelData

            width: list.width
            entry: modelData
            now: popup.now
            onActivated: {
                opener.command = [popup.script, "open", String(modelData.id)];
                opener.running = true;
            }
            onDismissed: popup.act(`dunstctl history-rm ${modelData.id}`)
        }
    }
}
