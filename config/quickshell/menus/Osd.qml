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
// toggleMute(), toggleMic(), brightness() and lockKey(). Shown above the bar
// on the focused monitor.
Scope {
    id: root

    property string kind: "volume" // volume | mic | brightness | caps | num
    property real value: 0 // 0..1
    property bool muted: false
    property bool shown: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    function show(kind, value, muted) {
        root.kind = kind;
        root.value = value;
        root.muted = muted;
        shown = true;
        hideTimer.restart();
    }

    // step in percent; never above 100 %, unmutes like the old binding did
    function volume(step) {
        const audio = sink?.audio;
        if (!audio)
            return;
        const next = Math.max(0, Math.min(1, Math.round(audio.volume * 100 + step) / 100));
        audio.muted = false;
        audio.volume = next;
        show("volume", next, false);
    }

    function toggleMute() {
        const audio = sink?.audio;
        if (!audio)
            return;
        audio.muted = !audio.muted;
        show("volume", audio.volume, audio.muted);
    }

    function toggleMic() {
        const audio = source?.audio;
        if (!audio)
            return;
        audio.muted = !audio.muted;
        show("mic", audio.volume, audio.muted);
    }

    // step in percent; keeps at least 5 % so the screen never goes dark
    function brightness(step) {
        brightnessProc.command = ["brightnessctl", "-m", "-n5%", "-e4", "set", `${Math.abs(step)}%${step < 0 ? "-" : "+"}`];
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

    // brightnessctl -m: device,class,current,percent,max
    Process {
        id: brightnessProc
        stdout: StdioCollector {
            onStreamFinished: {
                const percent = parseInt(text.trim().split(",")[3]);
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
        implicitWidth: pill.implicitWidth
        implicitHeight: pill.implicitHeight
        visible: root.shown || pill.opacity > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {} // clicks go through

        WlrLayershell.namespace: "quickshell-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: pill

            readonly property color accent: root.muted ? Theme.overlay0 : Theme.lavender

            implicitWidth: row.implicitWidth + 44
            implicitHeight: 52
            radius: height / 2
            color: Theme.crust
            border.width: 2
            border.color: Theme.surface0
            opacity: root.shown ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            RowLayout {
                id: row

                anchors.centerIn: parent
                spacing: 14

                Label {
                    Layout.preferredWidth: 24
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 20
                    color: pill.accent
                    text: {
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

                // Caps Lock / Num Lock: name and an On/Off pill
                Label {
                    visible: root.kind === "caps" || root.kind === "num"
                    Layout.preferredWidth: 150
                    text: root.kind === "caps" ? "Caps Lock" : "Num Lock"
                    font.pixelSize: 13
                    font.bold: true
                }
                Rectangle {
                    visible: root.kind === "caps" || root.kind === "num"
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
                    visible: root.kind !== "caps" && root.kind !== "num"
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
                    visible: root.kind !== "caps" && root.kind !== "num"
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
