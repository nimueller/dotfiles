import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// What the bar's privacy chip shows, part of daemon.qml: whether something
// records the microphone, uses a camera or shares the screen.
//  - Microphone: PipeWire recording streams, minus the level meters of mixers
//    like pavucontrol (stream.monitor).
//  - Screen: xdg-desktop-portal-hyprland's stream nodes, which only exist
//    while a screen or window is shared.
//  - Camera: browsers open /dev/video* directly rather than through PipeWire,
//    so this looks for any process holding a video device open (PipeWire
//    included, while an app streams the camera through it), every 2 s.
Item {
    id: root

    readonly property var recordings: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)

    readonly property bool microphone: recordings.some(n => n.properties["stream.monitor"] !== "true")
    readonly property bool screen: Pipewire.nodes.values.some(n => n.name.startsWith("xdph-streaming"))
    property bool camera: false

    readonly property bool active: microphone || screen || camera

    // properties is only filled in for bound nodes
    PwObjectTracker {
        objects: root.recordings
    }

    Process {
        id: devices
        command: ["sh", "-c", 'set -- /dev/video*; [ -e "$1" ] || exit 0; find /proc/[0-9]*/fd -lname "/dev/video*" -print -quit 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: root.camera = text.trim() !== ""
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: devices.running = true
    }
}
