pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// The media player the bar and the sound menu control (MPRIS): the one
// playing, or else the one that played last. playerctld is left out, it only
// mirrors the others, and so are browsers' players while they have no track.
Singleton {
    id: root

    readonly property var players: Mpris.players.values.filter(p => !p.dbusName.endsWith(".playerctld") && (p.isPlaying || !!p.trackTitle))
    readonly property var playing: players.find(p => p.isPlaying) ?? null
    property var last: null
    readonly property var player: playing ?? (players.includes(last) ? last : players[0]) ?? null

    onPlayingChanged: if (playing)
        last = playing

    // The track's title, or the player's name when it sends none
    function title(p) {
        return p?.trackTitle || name(p);
    }

    // The artist, or else the album
    function artist(p) {
        return p?.trackArtist || p?.trackAlbum || "";
    }

    // 3:07, 1:02:45
    function time(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor(s / 60) % 60;
        const sec = String(s % 60).padStart(2, "0");
        return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
    }

    // Electron apps send no desktop entry, only their app ID as the identity.
    // The entries load after the shell starts: reading the list makes the
    // bindings ask again then.
    function entry(p) {
        const id = p?.desktopEntry || p?.identity;
        return id && DesktopEntries.applications.values.length >= 0 ? DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id) : null;
    }

    // The app's name, from its desktop entry
    function name(p) {
        return entry(p)?.name || p?.identity || "";
    }

    // The player's icon from its desktop entry, if it has one
    function icon(p) {
        const icon = entry(p)?.icon;
        return icon ? Quickshell.iconPath(icon, true) : "";
    }
}
