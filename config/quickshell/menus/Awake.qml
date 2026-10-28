pragma Singleton

import Quickshell

// Stay awake by hand: the system menu's switch (system.qml) sets it,
// StayAwake.qml holds the inhibitor for it. It lasts as long as the daemon,
// so a forgotten switch ends at the next login at the latest. Unlike the
// stay-awake script it inhibits only idle, not sleep: closing the lid still
// suspends.
Singleton {
    property bool manual: false
}
