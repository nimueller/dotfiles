pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The shell's language: English, or German from translations/de.json, as
// chosen in Machine Settings (LocalSettings.qml), else the system's
// (LC_ALL, LC_MESSAGES, LANG). The Python helpers decide the same way
// (i18n.py).
//
// tr("%1 updates", count) looks the English text up and fills in %1, %2, …;
// a text without a translation stays English. Bindings that call tr() read
// `strings`, so they change along with the language. tests/test_translations.py
// checks that every text passed to tr() has its translation.
Singleton {
    id: root

    readonly property var languages: ["en", "de"]

    readonly property string systemLanguage: {
        const variables = ["LC_ALL", "LC_MESSAGES", "LANG"];
        const locale = variables.map(v => Quickshell.env(v) ?? "").find(v => v !== "") ?? "";
        const code = locale.slice(0, 2);
        return languages.includes(code) ? code : "en";
    }
    readonly property string language: {
        const chosen = LocalSettings.language;
        return languages.includes(chosen) ? chosen : systemLanguage;
    }
    // For dates and numbers: the system's own one when it's in the language,
    // so its region's formats stay; Qt's own data for the language otherwise,
    // also when the system's locale isn't generated and Qt fell back to "C"
    readonly property var locale: Qt.locale().name.startsWith(language) ? Qt.locale() : Qt.locale(language)

    property var german: ({})
    readonly property var strings: language === "de" ? german : ({})

    function tr(text, ...args) {
        const translated = strings[text] ?? text;
        return translated.replace(/%(\d)/g, (placeholder, n) => String(args[n - 1] ?? placeholder));
    }

    // Day and month names in the shell's language, e.g. formatDate(day, "dddd, d MMMM")
    function formatDate(date, format) {
        return date.toLocaleDateString(locale, format);
    }

    function formatDateTime(date, format) {
        return date.toLocaleString(locale, format);
    }

    FileView {
        path: Quickshell.shellPath("translations/de.json")
        blockLoading: true
        onLoaded: {
            try {
                root.german = JSON.parse(text());
            } catch (e) {
                console.warn(`translations/de.json: ${e}`);
            }
        }
    }
}
