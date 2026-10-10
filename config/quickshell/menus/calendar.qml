import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Calendar for the waybar clock: month grid, the selected day's events from
// Nextcloud (CalDAV through calendar-dav.py, one or more calendars) and a
// weather forecast from Open-Meteo. The gear opens the settings.
//
// Settings: ~/.local/state/quickshell-calendar.json (the app password is in
// the keyring). Last events and weather are cached in
// ~/.cache/quickshell-calendar.json so the menu shows them right away.
Popup {
    id: popup

    name: "calendar"
    centered: true
    cardWidth: 700

    readonly property string home: Quickshell.env("HOME")
    readonly property string helper: Quickshell.shellPath("calendar-dav.py")

    property var settings: ({}) // { location: { name, lat, lon }, nextcloud: { url, user, calendars } }
    property var cache: ({}) // { weather: { at, place, data }, events: { "yyyy-MM": [...] } }
    property bool editing: false

    property date today: new Date()
    property date selected: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    property bool syncing: false
    property string syncError: ""
    property string weatherError: ""
    property var locationResults: []
    property bool accountBusy: false
    property string accountError: ""
    property var prefill: ({})
    property int filesReady: 0 // settings and cache loaded (or missing)

    readonly property var nextcloud: settings.nextcloud ?? null
    readonly property var calendars: nextcloud?.calendars ?? []
    readonly property var enabled: calendars.filter(c => c.enabled)
    readonly property var colours: byHref(enabled, c => c.color)

    // First and last (exclusive) day of the six-week grid
    readonly property date gridStart: {
        const d = new Date(viewYear, viewMonth, 1);
        return new Date(viewYear, viewMonth, 1 - (d.getDay() + 6) % 7);
    }
    readonly property date gridEnd: new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + 42)
    readonly property string viewKey: Qt.formatDate(new Date(viewYear, viewMonth, 1), "yyyy-MM")

    readonly property var events: (cache.events?.[viewKey] ?? []).filter(e => colours[e.calendar]).map(e => ({
                title: e.title,
                location: e.location,
                allDay: e.allDay,
                calendar: e.calendar,
                start: parseTime(e.start, e.allDay),
                end: parseTime(e.end, e.allDay)
            }))
    readonly property var dots: {
        const out = {};
        for (const e of events) {
            for (let d = new Date(e.start.getFullYear(), e.start.getMonth(), e.start.getDate()); d < e.end || +d === +e.start; d.setDate(d.getDate() + 1)) {
                const key = Qt.formatDate(d, "yyyy-MM-dd");
                if (!out[key])
                    out[key] = [];
                const list = out[key];
                if (!list.includes(colours[e.calendar]))
                    list.push(colours[e.calendar]);
                if (+e.end === +e.start)
                    break;
            }
        }
        return out;
    }
    readonly property var dayEvents: {
        const from = new Date(selected.getFullYear(), selected.getMonth(), selected.getDate());
        const to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 1);
        return events.filter(e => e.start < to && (e.end > from || (+e.end === +e.start && e.start >= from))).sort((a, b) => b.allDay - a.allDay || a.start - b.start);
    }

    // { href: value(calendar) } (Qt's JS engine has no Object.fromEntries)
    function byHref(list, value) {
        const out = {};
        for (const c of list)
            out[c.href] = value(c);
        return out;
    }

    // All-day dates are local days; timed events carry their offset
    function parseTime(value, allDay) {
        if (!allDay)
            return new Date(value);
        const [y, m, d] = value.split("-").map(Number);
        return new Date(y, m - 1, d);
    }

    function saveSettings() {
        settingsFile.setText(JSON.stringify(settings, null, 2));
    }

    function saveCache() {
        cacheFile.setText(JSON.stringify(cache));
    }

    function shiftMonth(by) {
        const d = new Date(viewYear, viewMonth + by, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
        fetchEvents();
    }

    function goToday() {
        today = new Date();
        selected = today;
        if (viewYear !== today.getFullYear() || viewMonth !== today.getMonth()) {
            viewYear = today.getFullYear();
            viewMonth = today.getMonth();
            fetchEvents();
        }
    }

    // Events -----------------------------------------------------------------

    function fetchEvents() {
        if (!nextcloud || enabled.length === 0)
            return;
        if (eventsProc.running) {
            eventsProc.again = true;
            return;
        }
        eventsProc.key = viewKey;
        eventsProc.command = [helper, "events", nextcloud.url, nextcloud.user, Qt.formatDate(gridStart, "yyyy-MM-dd"), Qt.formatDate(gridEnd, "yyyy-MM-dd"), ...enabled.map(c => c.href)];
        syncing = true;
        eventsProc.running = true;
    }

    Process {
        id: eventsProc

        property string key: ""
        property bool again: false

        stdout: StdioCollector {
            onStreamFinished: {
                popup.syncing = false;
                let result;
                try {
                    result = JSON.parse(text);
                } catch (e) {
                    result = { error: "The calendar helper failed" };
                }
                if (result.error) {
                    popup.syncError = result.error;
                    return;
                }
                popup.syncError = "";
                const events = Object.assign({}, popup.cache.events);
                events[eventsProc.key] = result.events;
                popup.cache = Object.assign({}, popup.cache, { events });
                popup.saveCache();
            }
        }
        onExited: {
            if (again) {
                again = false;
                popup.fetchEvents();
            }
        }
    }

    // Nextcloud account --------------------------------------------------------

    function mergeCalendars(found) {
        const old = byHref(calendars, c => c.enabled);
        return found.map(c => Object.assign({}, c, { enabled: old[c.href] ?? true }));
    }

    function account(args, input, done) {
        accountBusy = true;
        accountError = "";
        accountProc.done = done;
        accountProc.input = input ?? "";
        accountProc.stdinEnabled = !!input;
        accountProc.command = [helper, ...args];
        accountProc.running = true;
    }

    function signIn(url, user, password) {
        account(["login", url, user], `${password}\n`, result => {
            settings = Object.assign({}, settings, { nextcloud: { url, user, calendars: mergeCalendars(result.calendars) } });
            saveSettings();
            fetchEvents();
        });
    }

    function refreshCalendars() {
        account(["calendars", nextcloud.url, nextcloud.user], "", result => {
            settings = Object.assign({}, settings, { nextcloud: Object.assign({}, nextcloud, { calendars: mergeCalendars(result.calendars) }) });
            saveSettings();
            fetchEvents();
        });
    }

    function signOut() {
        account(["logout", nextcloud.url, nextcloud.user], "", () => {});
        const next = Object.assign({}, settings);
        delete next.nextcloud;
        settings = next;
        cache = Object.assign({}, cache, { events: {} });
        saveSettings();
        saveCache();
    }

    function toggleCalendar(href) {
        const list = calendars.map(c => c.href === href ? Object.assign({}, c, { enabled: !c.enabled }) : c);
        settings = Object.assign({}, settings, { nextcloud: Object.assign({}, nextcloud, { calendars: list }) });
        saveSettings();
        fetchEvents();
    }

    Process {
        id: accountProc

        property var done: null
        property string input: ""

        onStarted: {
            if (input) {
                write(input);
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                popup.accountBusy = false;
                accountProc.input = "";
                let result;
                try {
                    result = JSON.parse(text);
                } catch (e) {
                    result = { error: "The calendar helper failed" };
                }
                if (result.error)
                    popup.accountError = result.error;
                else if (accountProc.done)
                    accountProc.done(result);
            }
        }
    }

    // Weather ------------------------------------------------------------------

    function get(url, done, fail) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            try {
                if (xhr.status !== 200)
                    throw new Error();
                done(JSON.parse(xhr.responseText));
            } catch (e) {
                fail();
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function fetchWeather(force) {
        const place = settings.location;
        if (!place) {
            zoneProc.running = true; // guess from the time zone first
            return;
        }
        const w = cache.weather;
        if (!force && w && w.place === place.name && Date.now() - w.at < 30 * 60 * 1000)
            return;
        weatherError = "";
        get(`https://api.open-meteo.com/v1/forecast?latitude=${place.lat}&longitude=${place.lon}&timezone=auto&forecast_days=7` + "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day" + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max", data => {
            cache = Object.assign({}, cache, { weather: { at: Date.now(), place: place.name, data } });
            saveCache();
        }, () => weatherError = "Couldn't load the weather");
    }

    function searchLocation(query, pickFirst) {
        get(`https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&format=json&name=${encodeURIComponent(query)}`, data => {
            const results = data.results ?? [];
            if (pickFirst && results.length)
                pickLocation(results[0]);
            else
                locationResults = results;
            if (!results.length)
                weatherError = `No place called “${query}” found`;
        }, () => weatherError = "Couldn't reach the location search");
    }

    function pickLocation(r) {
        locationResults = [];
        settings = Object.assign({}, settings, { location: { name: [r.name, r.country].filter(x => x).join(", "), lat: r.latitude, lon: r.longitude } });
        saveSettings();
        fetchWeather(true);
    }

    // No location yet: start with the city of the system time zone
    Process {
        id: zoneProc
        command: ["readlink", "-f", "/etc/localtime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const city = text.trim().split("/").pop().replace(/_/g, " ");
                if (city)
                    popup.searchLocation(city, true);
                else
                    popup.weatherError = "Set a location in the settings";
            }
        }
    }

    // Files --------------------------------------------------------------------

    FileView {
        id: settingsFile
        path: `${popup.home}/.local/state/quickshell-calendar.json`
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                popup.settings = JSON.parse(text());
            } catch (e) {}
            popup.filesReady++;
        }
        onLoadFailed: popup.filesReady++
    }

    FileView {
        id: cacheFile
        path: `${popup.home}/.cache/quickshell-calendar.json`
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                popup.cache = JSON.parse(text());
            } catch (e) {}
            popup.filesReady++;
        }
        onLoadFailed: popup.filesReady++
    }

    // Pre-fill the sign-in form from the Nextcloud desktop client
    FileView {
        path: `${popup.home}/.config/Nextcloud/nextcloud.cfg`
        printErrors: false
        onLoaded: {
            const cfg = text();
            popup.prefill = {
                url: cfg.match(/^\d+\\url=(.*)$/m)?.[1] ?? "",
                user: cfg.match(/^\d+\\dav_user=(.*)$/m)?.[1] ?? ""
            };
        }
    }

    // Fetch once we know the settings and what's cached
    onFilesReadyChanged: {
        if (filesReady === 2) {
            fetchWeather(false);
            fetchEvents();
        }
    }

    // Keep "today" right across midnight
    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: {
            const now = new Date();
            if (now.getDate() !== popup.today.getDate())
                popup.today = now;
        }
    }

    // Layout -------------------------------------------------------------------

    Header {
        glyph: Theme.glyph(0xf00ed) // 󰃭
        accent: Theme.mauve
        title: popup.editing ? "Calendar settings" : Qt.formatDate(popup.today, "dddd, d MMMM yyyy")

        IconButton {
            visible: !popup.editing && !!popup.nextcloud
            glyph: Theme.glyph(0xf0450) // 󰑐
            text: popup.syncing ? "Syncing…" : ""
            onClicked: {
                popup.fetchEvents();
                popup.fetchWeather(true);
            }
        }
        IconButton {
            glyph: Theme.glyph(popup.editing ? 0xf012c : 0xf0493) // 󰄬 / 󰒓
            text: popup.editing ? "Done" : ""
            accent: Theme.mauve
            active: popup.editing
            onClicked: {
                popup.editing = !popup.editing;
                popup.accountError = "";
                popup.locationResults = [];
            }
        }
    }

    // Main view: month and weather side by side, the day's events below
    RowLayout {
        Layout.fillWidth: true
        visible: !popup.editing
        spacing: 16

        MonthGrid {
            Layout.preferredWidth: 360
            Layout.alignment: Qt.AlignTop
            year: popup.viewYear
            month: popup.viewMonth
            today: popup.today
            selected: popup.selected
            dots: popup.dots
            onPicked: day => {
                popup.selected = day;
                if (day.getMonth() !== popup.viewMonth)
                    popup.shiftMonth(day < new Date(popup.viewYear, popup.viewMonth, 1) ? -1 : 1);
            }
            onShift: months => popup.shiftMonth(months)
            onReset: popup.goToday()
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Theme.surface0
        }

        WeatherPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            weather: popup.cache.weather?.data ?? null
            place: popup.settings.location?.name.split(",")[0] ?? ""
            error: popup.weatherError
            onConfigure: popup.editing = true
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !popup.editing
        spacing: 8

        SectionTitle {
            readonly property int offset: Math.round((new Date(popup.selected.getFullYear(), popup.selected.getMonth(), popup.selected.getDate()) - new Date(popup.today.getFullYear(), popup.today.getMonth(), popup.today.getDate())) / 86400000)

            text: (offset === 0 ? "Today · " : offset === 1 ? "Tomorrow · " : offset === -1 ? "Yesterday · " : "") + Qt.formatDate(popup.selected, "dddd, d MMMM")
        }

        // Not connected yet
        RowLayout {
            Layout.fillWidth: true
            visible: !popup.nextcloud
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: "Connect your Nextcloud to see your events here."
                color: Theme.overlay1
            }
            IconButton {
                glyph: Theme.glyph(0xf0342) // 󰍂
                text: "Connect"
                accent: Theme.blue
                active: true
                onClicked: popup.editing = true
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !!popup.syncError
            text: popup.syncError
            font.pixelSize: 10
            color: Theme.red
            wrapMode: Text.Wrap
        }

        Label {
            visible: !!popup.nextcloud && popup.dayEvents.length === 0
            text: popup.syncing && !(popup.viewKey in (popup.cache.events ?? {})) ? "Loading events…" : "Nothing planned"
            color: Theme.overlay0
            font.italic: true
        }

        ListView {
            id: eventList

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 240)
            visible: popup.dayEvents.length > 0
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: popup.dayEvents

            delegate: EventRow {
                required property var modelData

                width: eventList.width
                event: modelData
                day: popup.selected
                colour: popup.colours[modelData.calendar] ?? Theme.lavender
            }
        }
    }

    // Settings view
    CalendarSettings {
        Layout.fillWidth: true
        visible: popup.editing
        location: popup.settings.location ?? null
        locationResults: popup.locationResults
        nextcloud: popup.nextcloud
        prefill: popup.prefill
        busy: popup.accountBusy
        error: popup.accountError || popup.weatherError
        onSearchLocation: query => popup.searchLocation(query, false)
        onPickLocation: place => popup.pickLocation(place)
        onSignIn: (url, user, password) => popup.signIn(url, user, password)
        onSignOut: popup.signOut()
        onRefreshCalendars: popup.refreshCalendars()
        onToggleCalendar: href => popup.toggleCalendar(href)
    }
}
