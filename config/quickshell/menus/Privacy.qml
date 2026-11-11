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
// When one of them starts being used, the OSD says so and by which apps;
// clicking the bar's chip lists them (PrivacyPanel.qml).
Item {
    id: root

    required property var osd // Osd.qml

    readonly property var recordings: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)
    readonly property var microphones: {
        const isTrue = (n, key) => String(n.properties[key]) === "true";
        const isMicrophone = n => !isTrue(n, "stream.monitor") && !isTrue(n, "stream.capture.sink");
        return recordings.filter(isMicrophone);
    }
    // Video recording streams: the screen's consumers (and PipeWire cameras')
    readonly property var videoStreams: Pipewire.nodes.values.filter(n => !n.audio && n.isStream && !n.isSink)

    readonly property bool microphone: microphones.length > 0
    readonly property bool screen: Pipewire.nodes.values.some(n => n.name === "xdg-desktop-portal-hyprland")
    property bool camera: false

    readonly property bool active: microphone || screen || camera

    // The apps using them, for the OSD and PrivacyPanel: { name, icon, pid,
    // window } each, named and drawn like in the sound menu; window is null
    // when the app has none
    property var cameraProcesses: [] // { pid, comm }
    readonly property var cameraUsers: unique(cameraProcesses.map(c => {
        const window = Windows.forPid(c.pid);
        const entry = Windows.entry(window);
        const iconNames = [entry?.icon, c.comm, Windows.launcherEntry(c.pid)?.icon];
        const icons = iconNames.map(i => i ? Quickshell.iconPath(i, true) : "");
        return {
            name: entry?.name || c.comm,
            icon: icons.find(i => i) ?? "",
            pid: c.pid,
            window
        };
    }))
    readonly property var microphoneUsers: unique(microphones.map(streamUser))
    readonly property var screenUsers: unique(videoStreams.map(streamUser))

    // Flatpaks send their PID inside the sandbox: theirs is the window's
    function streamUser(node) {
        const p = Audio.props(node);
        const appId = p["pipewire.access.portal.app_id"];
        const ownPid = parseInt(p["application.process.id"]);
        let window = null;
        if (appId) {
            window = Windows.forApp(p["application.icon-name"]) ?? Windows.forApp(appId);
        } else if (ownPid > 0) {
            window = Windows.forPid(ownPid);
        }
        const pid = appId ? window?.lastIpcObject?.pid : ownPid;
        return {
            name: Audio.appName(node),
            icon: Audio.appIcon(node),
            pid: pid > 0 ? pid : 0,
            window
        };
    }

    function unique(users) {
        const seen = new Set();
        return users.filter(u => {
            const key = `${u.name}:${u.pid}`;
            return !seen.has(key) && seen.add(key);
        });
    }

    // properties is only filled in for bound nodes
    PwObjectTracker {
        objects: [...root.recordings, ...root.videoStreams]
    }

    // The names of the processes holding a camera open
    Process {
        id: devices
        command: ["sh", "-c", 'set -- /dev/video*; [ -e "$1" ] || exit 0; find /proc/[0-9]*/fd -lname "/dev/video*" 2>/dev/null | cut -d/ -f3 | sort -u | while read -r pid; do echo "$pid $(cat "/proc/$pid/comm")"; done 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const holders = text.split("\n").filter(l => / ./.test(l)).map(l => ({
                            pid: parseInt(l),
                            comm: l.slice(l.indexOf(" ") + 1)
                        }));
                root.cameraProcesses = holders.filter(h => h.comm !== "pipewire" && h.comm !== "wireplumber");
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
    property var announced: ({
            camera: false,
            microphone: false,
            screen: false
        })
    property bool started: false

    // "Camera is in use", "Camera and microphone are in use"; the devices in
    // the order they're listed in, the first one capitalised
    function message(devices) {
        if (devices.length === 1) {
            const single = {
                camera: I18n.tr("Camera is in use"),
                microphone: I18n.tr("Microphone is in use"),
                screen: I18n.tr("Screen is shared")
            };
            return single[devices[0]];
        }
        const first = {
            camera: I18n.tr("Camera"),
            microphone: I18n.tr("Microphone"),
            screen: I18n.tr("Screen")
        };
        const later = {
            camera: I18n.tr("camera"),
            microphone: I18n.tr("microphone"),
            screen: I18n.tr("screen")
        };
        const names = devices.map((device, i) => i === 0 ? first[device] : later[device]);
        const listed = I18n.tr("%1 and %2", names.slice(0, -1).join(", "), names[names.length - 1]);
        return I18n.tr("%1 are in use", listed);
    }

    onCameraChanged: settle.restart()
    onMicrophoneChanged: settle.restart()
    onScreenChanged: settle.restart()

    Timer {
        id: settle
        interval: 1000
        onTriggered: {
            const now = {
                camera: root.camera,
                microphone: root.microphone,
                screen: root.screen
            };
            const started = ["camera", "microphone", "screen"].filter(k => now[k] && !root.announced[k]);
            root.announced = now;
            if (!root.started || started.length === 0) {
                return;
            }
            const users = {
                camera: root.cameraUsers,
                microphone: root.microphoneUsers,
                screen: root.screenUsers
            };
            const userNames = [].concat(...started.map(k => users[k].map(u => u.name)));
            root.osd.privacy(started[0], message(started), [...new Set(userNames)].join(", "));
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
