import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland

// On-screen display for the volume, microphone and brightness keys and for
// Caps Lock / Num Lock (replaces SwayOSD), part of daemon.qml. The keys send
// Hyprland events (see keybinds.lua) that daemon.qml passes to volume(),
// toggleMute(), toggleMic(), brightness() and lockKey(); StayAwake.qml calls
// awake(), Privacy.qml privacy(). Bluetooth headphones' own volume buttons
// show it too (deviceChange() below). Shown above the bar on the focused
// monitor.
Scope {
    id: root

    property string kind: "volume" // volume | mic | brightness | caps | num | awake | privacy
    property real value: 0 // 0..1
    property bool muted: false
    property string title: "" // privacy: what is in use
    property string detail: "" // awake: why; privacy: by which apps
    property string device: "" // privacy: camera | microphone | screen
    property bool shown: false

    readonly property bool toggle: kind === "caps" || kind === "num" || kind === "awake" || kind === "privacy"

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    function show(kind, value, muted) {
        root.kind = kind;
        root.value = value;
        root.muted = muted;
        shown = true;
        hideTimer.interval = kind === "awake" || kind === "privacy" ? 3000 : 1500;
        hideTimer.restart();
    }

    // The screen stays awake (on) or locks when idle again (off)
    function awake(on, why) {
        detail = why;
        show("awake", on ? 1 : 0, !on);
    }

    // A camera, the microphone or the screen started being used
    function privacy(what, text, apps) {
        device = what;
        title = text;
        detail = apps;
        show("privacy", 1, false);
    }

    // step in percent; never above 100 %, unmutes like the old binding did
    function volume(step) {
        const audio = sink?.audio;
        if (!audio)
            return;
        const next = Math.max(0, Math.min(1, Math.round(audio.volume * 100 + step) / 100));
        Audio.setMuted(sink, false);
        Audio.setVolume(sink, next);
        show("volume", next, false);
    }

    function toggleMute() {
        const audio = sink?.audio;
        if (!audio)
            return;
        Audio.setMuted(sink, !audio.muted);
        show("volume", audio.volume, audio.muted);
    }

    function toggleMic() {
        const audio = source?.audio;
        if (!audio)
            return;
        audio.muted = !audio.muted;
        show("mic", audio.volume, audio.muted);
    }

    // step in percent. The focused monitor over DDC/CI (Ddc.qml) when it
    // answers, otherwise the backlight (backlight.sh: the same scale as the
    // system menu, never so low the screen goes dark).
    function brightness(step) {
        const monitor = window.screen?.name ?? "";
        if (ddc.has(monitor)) {
            ddc.step(monitor, step);
            return;
        }
        brightnessProc.command = [Quickshell.shellPath("backlight.sh"), "step", String(step)];
        brightnessProc.running = true;
    }

    // Caps Lock / Num Lock. Caps Lock turns on when the key goes down but
    // off only when it comes back up, so the state read right after the press
    // can still be the old one. Show the flipped last known state at once,
    // then confirm it from the main keyboard (every 80 ms for about a second;
    // if it never matches, e.g. another keyboard changed it, show the real one).
    property var locks: ({ caps: false, num: false })
    property string lockWhich: "caps"
    property bool lockExpected: false
    property int lockTries: 0

    function lockKey(which) {
        lockWhich = which;
        lockExpected = !locks[which];
        lockTries = 0;
        show(which, lockExpected ? 1 : 0, !lockExpected);
        lockPoll.restart();
    }

    Timer {
        id: lockPoll
        interval: 80
        repeat: true
        onTriggered: lockProc.running = true
    }

    Process {
        id: lockProc

        command: ["hyprctl", "devices", "-j"]
        running: true // the state at startup
        stdout: StdioCollector {
            onStreamFinished: {
                let keyboard;
                try {
                    keyboard = JSON.parse(text).keyboards.find(k => k.main);
                } catch (e) {
                    return;
                }
                if (!keyboard)
                    return;
                root.locks = { caps: keyboard.capsLock, num: keyboard.numLock };
                if (!lockPoll.running)
                    return;
                const actual = root.locks[root.lockWhich];
                if (actual === root.lockExpected || ++root.lockTries >= 12) {
                    lockPoll.stop();
                    if (actual !== root.lockExpected)
                        root.show(root.lockWhich, actual ? 1 : 0, !actual);
                }
            }
        }
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    // Bluetooth headphones with AVRCP absolute volume change it themselves:
    // no key event reaches Hyprland, only the sink's volume changes. Show
    // those changes, but not the shell's own (Audio.localChange: bar, menus,
    // the keys above) nor the first ones of a sink that just connected or
    // became the default.
    readonly property bool bluetooth: sink?.name?.startsWith("bluez_output.") ?? false
    readonly property real sinkVolume: sink?.audio?.volume ?? 0
    readonly property bool sinkMuted: sink?.audio?.muted ?? false

    onSinkChanged: settling.restart()
    onSinkVolumeChanged: deviceChange()
    onSinkMutedChanged: deviceChange()

    function deviceChange() {
        if (!bluetooth || !sink.ready || settling.running || Date.now() - Audio.localChange < 500)
            return;
        show("volume", sinkVolume, sinkMuted);
    }

    Timer {
        id: settling
        interval: 1500
        running: true
    }

    Ddc {
        id: ddc
        onChanged: (name, value) => root.show("brightness", value, false)
    }

    // backlight.sh: the percent afterwards
    Process {
        id: brightnessProc
        stdout: StdioCollector {
            onStreamFinished: {
                const percent = parseInt(text);
                if (!isNaN(percent))
                    root.show("brightness", percent / 100, false);
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.shown = false
    }

    PanelWindow {
        id: window

        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors.bottom: true
        margins.bottom: 64
        implicitWidth: pill.implicitWidth + 16
        implicitHeight: pill.implicitHeight + 16 // room to rise into place
        visible: root.shown || pill.opacity > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {} // clicks go through

        WlrLayershell.namespace: "quickshell-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Same look as the notification popups: crust card, thin outline,
        // icon on a tinted chip. Rises and grows in, sinks and fades out.
        Rectangle {
            id: pill

            readonly property color accent: root.kind === "privacy" ? Theme.peach : root.muted ? Theme.overlay0 : Theme.lavender

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            implicitWidth: row.implicitWidth + 28
            implicitHeight: 56
            radius: height / 2
            color: Theme.crust
            border.width: 1
            border.color: Theme.surface0
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.92
            transform: Translate { y: root.shown ? 0 : 12; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

            RowLayout {
                id: row

                anchors.centerIn: parent
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 19
                    color: Theme.alpha(pill.accent, 0.15)

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Label {
                        anchors.centerIn: parent
                        font.pixelSize: 18
                        color: pill.accent
                        text: {
                            if (root.kind === "privacy")
                                return Theme.glyph({ camera: 0xf05a0, microphone: 0xf036c, screen: 0xf0379 }[root.device]); // 󰖠 󰍬 󰍹
                            if (root.kind === "awake")
                                return Theme.glyph(root.muted ? 0xf04b2 : 0xf0176); // 󰒲 / 󰅶
                            if (root.kind === "caps")
                                return Theme.glyph(0xf0632); // 󰘲
                            if (root.kind === "num")
                                return Theme.glyph(0xf061c); // 󰘜
                            if (root.kind === "mic")
                                return Theme.glyph(root.muted ? 0xf036d : 0xf036c); // 󰍭 / 󰍬
                            if (root.kind === "brightness")
                                return Theme.glyph(root.value < 0.34 ? 0xf00de : root.value < 0.67 ? 0xf00df : 0xf00e0); // 󰃞 󰃟 󰃠
                            return Audio.volumeIcon({ volume: root.value, muted: root.muted });
                        }
                    }
                }

                // Caps Lock / Num Lock / Stay awake / privacy: name (and why or
                // by whom) and an On/Off pill (not for privacy)
                Column {
                    visible: root.toggle
                    Layout.preferredWidth: root.kind === "privacy" ? 300 : root.kind === "awake" ? 240 : 150
                    spacing: 2

                    Label {
                        width: parent.width
                        text: root.kind === "caps" ? "Caps Lock" : root.kind === "num" ? "Num Lock" : root.kind === "privacy" ? root.title : "Stay awake"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Label {
                        visible: (root.kind === "awake" || root.kind === "privacy") && !!root.detail
                        width: parent.width
                        text: root.detail
                        font.pixelSize: 11
                        color: Theme.subtext0
                    }
                }
                Rectangle {
                    visible: root.toggle && root.kind !== "privacy"
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 22
                    radius: 11
                    color: root.muted ? Theme.surface0 : Theme.lavender

                    Label {
                        anchors.centerIn: parent
                        text: root.muted ? "Off" : "On"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.muted ? Theme.overlay1 : Theme.crust
                    }
                }

                // Level
                Rectangle {
                    visible: !root.toggle
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 8
                    radius: 4
                    color: Theme.surface0

                    Rectangle {
                        width: parent.width * Math.min(1, root.value)
                        height: parent.height
                        radius: 4
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.muted ? Theme.overlay0 : Theme.lavender }
                            GradientStop { position: 1; color: root.muted ? Theme.overlay0 : Theme.mauve }
                        }

                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                }

                Label {
                    visible: !root.toggle
                    Layout.preferredWidth: 46
                    horizontalAlignment: Text.AlignRight
                    text: root.muted ? "Muted" : `${Math.round(root.value * 100)}%`
                    font.pixelSize: 13
                    font.bold: true
                    color: root.muted ? Theme.overlay1 : Theme.text
                }
            }
        }
    }
}
