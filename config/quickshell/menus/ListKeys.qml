pragma Singleton

import QtQuick
import Quickshell

// The keys that move through a list of results (the launcher, the clipboard
// history): the arrows, Tab and Backtab, and Ctrl with J/N or K/P
Singleton {
    function isDown(event) {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            return true;
        }
        const ctrl = event.modifiers & Qt.ControlModifier;
        return !!ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N);
    }

    function isUp(event) {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            return true;
        }
        const ctrl = event.modifiers & Qt.ControlModifier;
        return !!ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P);
    }
}
