import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

// Keeps the screen awake (no idle lock, monitors stay on; hypridle.conf)
// while a browser or video player is playing, a game runs or Sunshine is
// streaming, part of daemon.qml. Pausing counts as idle again, and music
// players don't count. Sunshine holds its own inhibitor: its prep commands
// (config/sunshine) run the stay-awake script (pkgs/scripts), which works
// without Quickshell and reports to it with the Hyprland event
// "quickshell-awake sunshine on|off". Changes show on the OSD, not as
// notifications.
Scope {
    id: root

    required property var osd // Osd.qml

    property bool sunshine: false

    // MPRIS players that play video: browsers and video players
    readonly property var videoApps: ["zen", "firefox", "librewolf", "chromium", "chrome", "brave", "vivaldi", "mpv", "vlc", "celluloid", "haruna", "totem", "kodi", "jellyfin"]

    readonly property var video: Mpris.players.values.find(p => p.isPlaying && videoApps.some(a => `${p.desktopEntry ?? ""} ${p.identity ?? ""}`.toLowerCase().includes(a))) ?? null

    // Game windows: Steam (and Proton) games, Wine programs, gamescope
    readonly property var game: ToplevelManager.toplevels.values.find(t => /^steam_app_|\.exe$|^gamescope$/i.test(t.appId ?? "")) ?? null

    readonly property string reason: sunshine ? "Sunshine is streaming" : game ? game.title || "A game is running" : video ? [video.identity, video.trackTitle].filter(s => s).join(": ") : ""
    readonly property bool wanted: reason !== ""

    // Playback flickers (buffering, ads, the next track): act on a change only
    // once it has lasted a moment, and show nothing for the state at startup
    property bool active: false
    property string shownReason: ""
    property bool started: false

    onWantedChanged: settle.restart()
    onReasonChanged: settle.restart()

    Timer {
        id: settle
        interval: 2000
        onTriggered: {
            if (root.wanted === root.active && (!root.wanted || root.reason === root.shownReason))
                return;
            const changed = root.wanted !== root.active;
            root.active = root.wanted;
            root.shownReason = root.reason;
            if (root.started && changed)
                root.osd.awake(root.active, root.active ? root.reason : "The screen locks when idle again");
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

    // The inhibitor sits on a tiny invisible overlay, which stays visible
    // above fullscreen windows (Hyprland ignores inhibitors of hidden surfaces)
    PanelWindow {
        id: holder

        anchors.top: true
        anchors.left: true
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        WlrLayershell.namespace: "quickshell-stay-awake"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        IdleInhibitor {
            window: holder
            enabled: root.active
        }
    }

    // Sunshine's state, after a restart of the daemon
    Process {
        running: true
        command: ["sh", "-c", 'kill -0 "$(cat "$XDG_RUNTIME_DIR/stay-awake-sunshine.pid" 2>/dev/null)" 2>/dev/null']
        onExited: code => root.sunshine = code === 0
    }

    function event(name, state) {
        if (name === "sunshine")
            sunshine = state === "on";
    }
}
