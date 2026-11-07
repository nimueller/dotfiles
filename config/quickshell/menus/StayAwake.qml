import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

// Keeps the screen awake (no idle lock, monitors stay on; hypridle.conf)
// while a browser or video player is playing, a game runs, Sunshine is
// streaming or the switch in the system menu is on (Awake.qml), part of
// daemon.qml. Pausing counts as idle again, and music
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
    readonly property var browsers: ["zen", "firefox", "librewolf", "chromium", "chrome", "brave", "vivaldi"]
    readonly property var videoPlayers: ["mpv", "vlc", "celluloid", "haruna", "totem", "kodi", "jellyfin"]
    readonly property var videoApps: [...browsers, ...videoPlayers]

    readonly property var video: {
        const isVideoApp = p => {
            const name = `${p.desktopEntry ?? ""} ${p.identity ?? ""}`.toLowerCase();
            return videoApps.some(a => name.includes(a));
        };
        return Mpris.players.values.find(p => p.isPlaying && isVideoApp(p)) ?? null;
    }

    // Game windows: Steam (and Proton) games, Wine programs, gamescope
    readonly property var game: {
        const isGame = t => /^steam_app_|\.exe$|^gamescope$/i.test(t.appId ?? "");
        return ToplevelManager.toplevels.values.find(isGame) ?? null;
    }

    readonly property string reason: {
        if (sunshine) {
            return "Sunshine is streaming";
        }
        if (Awake.manual) {
            return "Until you turn it off";
        }
        if (game) {
            return game.title || "A game is running";
        }
        if (video) {
            return [video.identity, video.trackTitle].filter(s => s).join(": ");
        }
        return "";
    }
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
            if (root.wanted === root.active && (!root.wanted || root.reason === root.shownReason)) {
                return;
            }
            const changed = root.wanted !== root.active;
            root.active = root.wanted;
            root.shownReason = root.reason;
            if (root.started && changed) {
                root.osd.awake(root.active, root.active ? root.reason : "The screen locks when idle again");
            }
        }
    }

    // The switch is a click: show it right away
    Connections {
        target: Awake

        function onManualChanged() {
            settle.stop();
            settle.triggered();
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

    // Sunshine's state, after a restart of the daemon. Without a pid file
    // there is nothing to check: sh (bash in POSIX mode) takes `kill -0 ""`
    // as success
    Process {
        running: true
        command: ["sh", "-c", 'pid=$(cat "$XDG_RUNTIME_DIR/stay-awake-sunshine.pid" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null']
        onExited: code => root.sunshine = code === 0
    }

    function event(name, state) {
        if (name === "sunshine") {
            sunshine = state === "on";
        }
    }
}
