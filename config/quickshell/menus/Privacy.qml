import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// What the bar's privacy chip shows, part of daemon.qml: whether something
// records the microphone, uses a camera or shares the screen.
//  - Microphone: PipeWire recording streams, minus the level meters of mixers
//    like pavucontrol (stream.monitor) and recordings of what plays
//    (stream.capture.sink, e.g. OBS's desktop audio).
//  - Screen: xdg-desktop-portal-hyprland's stream nodes, which only exist
//    while a screen or window is shared (OBS: while a screen capture source
//    exists, not only while recording).
//  - Camera: browsers open /dev/video* directly rather than through PipeWire,
//    so this looks for any process holding a video device open (PipeWire
//    included, while an app streams the camera through it), every 2 s.
// When one of them starts being used, the OSD says so and by which apps.
Item {
    id: root

    required property var osd // Osd.qml

    readonly property var recordings: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)
    readonly property var microphones: recordings.filter(n => String(n.properties["stream.monitor"]) !== "true" && String(n.properties["stream.capture.sink"]) !== "true")
    // Video recording streams: the screen's consumers (and PipeWire cameras')
    readonly property var videoStreams: Pipewire.nodes.values.filter(n => !n.audio && n.isStream && !n.isSink)

    readonly property bool microphone: microphones.length > 0
    readonly property bool screen: Pipewire.nodes.values.some(n => n.name === "xdg-desktop-portal-hyprland")
    property bool camera: false

    readonly property bool active: microphone || screen || camera

    property var cameraApps: []

    function apps(nodes) {
        return [...new Set(nodes.map(n => n.properties["application.name"] || n.name).filter(a => a))];
    }

    // properties is only filled in for bound nodes
    PwObjectTracker {
        objects: [...root.recordings, ...root.videoStreams]
    }

    // The names of the processes holding a camera open
    Process {
        id: devices
        command: ["sh", "-c", 'set -- /dev/video*; [ -e "$1" ] || exit 0; find /proc/[0-9]*/fd -lname "/dev/video*" 2>/dev/null | cut -d/ -f3 | sort -u | while read -r pid; do cat "/proc/$pid/comm"; done 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const holders = [...new Set(text.split("\n").filter(l => l))];
                root.cameraApps = holders.filter(h => h !== "pipewire" && h !== "wireplumber");
                root.camera = holders.length > 0;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: devices.running = true
    }

    // OSD when a device starts being used. Streams come and go while apps
    // start up: act once a change has lasted a moment, and show nothing for
    // what is already in use when the daemon starts.
    property var announced: ({ camera: false, microphone: false, screen: false })
    property bool started: false

    onCameraChanged: settle.restart()
    onMicrophoneChanged: settle.restart()
    onScreenChanged: settle.restart()

    Timer {
        id: settle
        interval: 1000
        onTriggered: {
            const now = { camera: root.camera, microphone: root.microphone, screen: root.screen };
            const started = ["camera", "microphone", "screen"].filter(k => now[k] && !root.announced[k]);
            root.announced = now;
            if (!root.started || started.length === 0)
                return;
            const names = { camera: "Camera", microphone: "Microphone", screen: "Screen" };
            const users = { camera: root.cameraApps, microphone: root.apps(root.microphones), screen: root.apps(root.videoStreams) };
            const title = started.map((k, i) => i === 0 ? names[k] : names[k].toLowerCase()).join(" and ") + (started.length > 1 ? " are" : " is") + (started.length === 1 && started[0] === "screen" ? " shared" : " in use");
            root.osd.privacy(started[0], title, [...new Set([].concat(...started.map(k => users[k])))].join(", "));
        }
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: {
            root.started = true;
            settle.restart();
        }
    }
}
