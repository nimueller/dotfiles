import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Calendar for the waybar clock: a month of day boxes with their
// appointments and forecast, the selected day in a sidebar with the current
// weather and an hourly forecast, and a form to add or edit appointments
// (with reminders) on Nextcloud. Events come from Nextcloud (CalDAV) and
// read-only ICS subscriptions via calendar-dav.py; the forecast from
// Open-Meteo, the current weather from the nearest airport's METAR
// (aviationweather.gov). The gear opens the settings.
//
// Settings: ~/.local/state/quickshell-calendar.json (the app password is in
// the keyring). Last events and weather are cached in
// ~/.cache/quickshell-calendar.json so the menu shows them right away.
Popup {
    id: popup

    name: "calendar"
    centered: true
    cardWidth: 1120

    readonly property string home: Quickshell.env("HOME")
    readonly property string helper: Quickshell.shellPath("calendar-dav.py")
    readonly property var palette: [Theme.peach, Theme.teal, Theme.pink, Theme.yellow, Theme.green, Theme.maroon, Theme.sky]

    property var settings: ({}) // { location, weekStart, weekNumbers, nextcloud: { url, user, calendars }, ics: [...] }
    property var cache: ({}) // { weather: { at, place, data }, events: { "yyyy-MM": [...] } }
    property bool editing: false
    property bool creating: false

    property date today: new Date()
    property date selected: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    property bool syncing: false
    property var syncErrors: ({})
    property string weatherError: ""
    property var locationResults: []
    property bool accountBusy: false
    property string accountError: ""
    property bool saving: false
    property string saveError: ""
    property var prefill: ({})
    property int filesReady: 0 // settings and cache loaded (or missing)

    readonly property int weekStart: settings.weekStart ?? 1
    readonly property bool weekNumbers: settings.weekNumbers ?? true
    readonly property var nextcloud: settings.nextcloud ?? null
    readonly property var subscriptions: settings.ics ?? []
    // Every enabled calendar: { id, color, writable }
    readonly property var sources: [
        ...(nextcloud?.calendars ?? []).filter(c => c.enabled).map(c => ({ id: c.href, color: c.color, writable: c.writable !== false })),
        ...subscriptions.filter(s => s.enabled).map(s => ({ id: s.id, color: s.color, writable: false }))
    ]
    readonly property var writable: (nextcloud?.calendars ?? []).filter(c => c.writable !== false)
    readonly property var colours: byId(sources, s => s.color)
    readonly property var canWrite: byId(sources, s => s.writable)

    // First and last (exclusive) day of the six-week grid
    readonly property date gridStart: {
        const d = new Date(viewYear, viewMonth, 1);
        return new Date(viewYear, viewMonth, 1 - (d.getDay() - weekStart + 7) % 7);
    }
    readonly property date gridEnd: new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + 42)
    readonly property string viewKey: Qt.formatDate(new Date(viewYear, viewMonth, 1), "yyyy-MM")

    readonly property var events: (cache.events?.[viewKey] ?? []).filter(e => colours[e.calendar]).map(e => ({
                title: e.title,
                location: e.location,
                allDay: e.allDay,
                calendar: e.calendar,
                colour: e.color || colours[e.calendar], // event colour, else its calendar's
                alarms: e.alarms ?? [],
                start: parseTime(e.start, e.allDay),
                end: parseTime(e.end, e.allDay),
                href: e.href ?? "",
                etag: e.etag ?? "",
                editable: !!e.href && !e.recurring && canWrite[e.calendar]
            })).sort((a, b) => b.allDay - a.allDay || a.start - b.start)
    // "yyyy-MM-dd" -> events touching that day
    readonly property var byDay: {
        const out = {};
        for (const e of events) {
            const zero = +e.end === +e.start;
            for (let d = new Date(e.start.getFullYear(), e.start.getMonth(), e.start.getDate()); d < e.end || (zero && +d <= +e.start); d.setDate(d.getDate() + 1)) {
                if (d >= gridEnd)
                    break;
                if (d < gridStart)
                    continue;
                const key = Qt.formatDate(d, "yyyy-MM-dd");
                if (!out[key])
                    out[key] = [];
                out[key].push(e);
            }
        }
        return out;
    }
    readonly property var dayEvents: byDay[Qt.formatDate(selected, "yyyy-MM-dd")] ?? []
    readonly property var forecast: Weather.daily(cache.weather?.data)
    readonly property string syncError: Object.values(syncErrors)[0] ?? ""

    function byId(list, value) {
        const out = {};
        for (const s of list)
            out[s.id] = value(s);
        return out;
    }

    // All-day dates are local days; timed events carry their offset
    function parseTime(value, allDay) {
        if (!allDay)
            return new Date(value);
        const [y, m, d] = value.split("-").map(Number);
        return new Date(y, m - 1, d);
    }

    function update(changes) {
        settings = Object.assign({}, settings, changes);
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

    function select(day) {
        selected = day;
        if (day.getFullYear() !== viewYear || day.getMonth() !== viewMonth) {
            viewYear = day.getFullYear();
            viewMonth = day.getMonth();
            fetchEvents();
        }
    }

    function goToday() {
        today = new Date();
        select(today);
    }

    function newAppointment(day) {
        select(day);
        saveError = "";
        creating = true;
        form.reset();
    }

    function editAppointment(event) {
        saveError = "";
        creating = true;
        form.edit(event);
    }

    // Helper calls --------------------------------------------------------------

    HelperCall {
        id: eventsCall
        helper: popup.helper
        property bool again: false
        onExited: {
            if (again) {
                again = false;
                popup.fetchEvents();
            }
        }
    }
    HelperCall {
        id: accountCall
        helper: popup.helper
    }
    HelperCall {
        id: writeCall
        helper: popup.helper
    }

    function fetchEvents() {
        if (sources.length === 0) {
            syncErrors = {};
            return;
        }
        if (eventsCall.running) {
            eventsCall.again = true;
            return;
        }
        const key = viewKey;
        const spec = {
            start: Qt.formatDate(gridStart, "yyyy-MM-dd"),
            end: Qt.formatDate(gridEnd, "yyyy-MM-dd"),
            nextcloud: nextcloud ? { url: nextcloud.url, user: nextcloud.user, calendars: nextcloud.calendars.filter(c => c.enabled).map(c => c.href) } : null,
            ics: subscriptions.filter(s => s.enabled).map(s => ({ id: s.id, url: s.url }))
        };
        syncing = true;
        eventsCall.run(["events"], JSON.stringify(spec), result => {
            syncing = false;
            syncErrors = result.errors;
            const events = Object.assign({}, cache.events);
            events[key] = result.events;
            cache = Object.assign({}, cache, { events });
            saveCache();
        }, error => {
            syncing = false;
            syncErrors = { all: error };
        });
    }

    function mergeCalendars(found) {
        const old = byId((nextcloud?.calendars ?? []).map(c => ({ id: c.href, enabled: c.enabled })), c => c.enabled);
        return found.map(c => Object.assign({}, c, { enabled: old[c.href] ?? true }));
    }

    function account(args, input, done) {
        accountBusy = true;
        accountError = "";
        accountCall.run(args, input, result => {
            accountBusy = false;
            done(result);
        }, error => {
            accountBusy = false;
            accountError = error;
        });
    }

    function signIn(url, user, password) {
        account(["login", url, user], `${password}\n`, result => {
            update({ nextcloud: { url, user, calendars: mergeCalendars(result.calendars) } });
            fetchEvents();
        });
    }

    function refreshCalendars() {
        account(["calendars", nextcloud.url, nextcloud.user], "", result => {
            update({ nextcloud: Object.assign({}, nextcloud, { calendars: mergeCalendars(result.calendars) }) });
            fetchEvents();
        });
    }

    function signOut() {
        account(["logout", nextcloud.url, nextcloud.user], "", () => {});
        const next = Object.assign({}, settings);
        delete next.nextcloud;
        settings = next;
        update({});
        fetchEvents();
    }

    function toggleCalendar(href) {
        update({ nextcloud: Object.assign({}, nextcloud, { calendars: nextcloud.calendars.map(c => c.href === href ? Object.assign({}, c, { enabled: !c.enabled }) : c) }) });
        fetchEvents();
    }

    function addSubscription(name, url) {
        const id = `ics:${Date.now().toString(36)}`;
        update({ ics: [...subscriptions, { id, name, url, color: `${palette[subscriptions.length % palette.length]}`, enabled: true }] });
        fetchEvents();
    }

    function toggleSubscription(id) {
        update({ ics: subscriptions.map(s => s.id === id ? Object.assign({}, s, { enabled: !s.enabled }) : s) });
        fetchEvents();
    }

    function removeSubscription(id) {
        update({ ics: subscriptions.filter(s => s.id !== id) });
        fetchEvents();
    }

    // New event, or an edited one (it has an href)
    function saveEvent(event) {
        saving = true;
        saveError = "";
        writeCall.run([event.href ? "update" : "create", nextcloud.url, nextcloud.user], JSON.stringify(event), () => {
            saving = false;
            creating = false;
            fetchEvents();
        }, error => {
            saving = false;
            saveError = error;
        });
    }

    function deleteEvent(event) {
        writeCall.run(["delete", nextcloud.url, nextcloud.user], JSON.stringify({ href: event.href, etag: event.etag }), () => fetchEvents(), error => syncErrors = { delete: error });
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
        if (!force && w && w.place === place.name && w.data?.hourly && Date.now() - w.at < 15 * 60 * 1000)
            return;
        weatherError = "";
        get(`https://api.open-meteo.com/v1/forecast?latitude=${place.lat}&longitude=${place.lon}&timezone=auto&forecast_days=16` + "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day" + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max" + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day", data => {
            cache = Object.assign({}, cache, { weather: { at: Date.now(), place: place.name, data, metar: cache.weather?.place === place.name ? cache.weather.metar : null } });
            saveCache();
            fetchMetar(place, 1);
        }, () => weatherError = "Couldn't load the weather");
    }

    // Current weather from the nearest airport with a recent METAR; looks
    // further out if there is none close by
    function fetchMetar(place, widen) {
        const dLat = 0.8 * widen, dLon = 1.2 * widen;
        get(`https://aviationweather.gov/api/data/metar?format=json&bbox=${place.lat - dLat},${place.lon - dLon},${place.lat + dLat},${place.lon + dLon}`, data => {
            const fresh = (data ?? []).filter(m => m.temp !== null && m.temp !== undefined && Date.now() / 1000 - m.obsTime < 3 * 3600);
            const nearest = fresh.map(m => Object.assign({}, m, { distance: Weather.distanceKm(place.lat, place.lon, m.lat, m.lon) })).sort((a, b) => a.distance - b.distance)[0];
            if (!nearest && widen < 3) {
                fetchMetar(place, widen + 1);
                return;
            }
            cache = Object.assign({}, cache, { weather: Object.assign({}, cache.weather, { metar: nearest ?? null }) });
            saveCache();
        }, () => {}); // keep Open-Meteo's current weather
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
        update({ location: { name: [r.name, r.country].filter(x => x).join(", "), lat: r.latitude, lon: r.longitude } });
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
            visible: !popup.editing && popup.writable.length > 0
            glyph: Theme.glyph(0xf0415) // 󰐕
            text: "New"
            accent: Theme.mauve
            active: popup.creating
            onClicked: popup.creating ? popup.creating = false : popup.newAppointment(popup.selected)
        }
        IconButton {
            visible: !popup.editing && popup.sources.length > 0
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

    // Main view: month on the left, weather and the selected day on the right
    RowLayout {
        Layout.fillWidth: true
        visible: !popup.editing
        spacing: 16

        MonthGrid {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            year: popup.viewYear
            month: popup.viewMonth
            today: popup.today
            selected: popup.selected
            weekStart: popup.weekStart
            weekNumbers: popup.weekNumbers
            events: popup.byDay
            forecast: popup.forecast
            onPicked: day => popup.select(day)
            onActivated: day => {
                if (popup.writable.length > 0)
                    popup.newAppointment(day);
            }
            onShift: months => popup.shiftMonth(months)
            onReset: popup.goToday()
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Theme.surface0
        }

        ColumnLayout {
            Layout.preferredWidth: 300
            Layout.maximumWidth: 300
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            spacing: 12

            WeatherPanel {
                Layout.fillWidth: true
                weather: popup.cache.weather?.data ?? null
                metar: popup.cache.weather?.metar ?? null
                place: popup.settings.location?.name.split(",")[0] ?? ""
                error: popup.weatherError
                onConfigure: popup.editing = true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.surface0
            }

            EventForm {
                id: form
                Layout.fillWidth: true
                visible: popup.creating
                day: popup.selected
                calendars: popup.writable
                busy: popup.saving
                error: popup.saveError
                onSaveRequested: event => popup.saveEvent(event)
                onCancelled: popup.creating = false
            }

            // The selected day
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !popup.creating
                spacing: 8

                SectionTitle {
                    readonly property int offset: Math.round((new Date(popup.selected.getFullYear(), popup.selected.getMonth(), popup.selected.getDate()) - new Date(popup.today.getFullYear(), popup.today.getMonth(), popup.today.getDate())) / 86400000)

                    Layout.fillWidth: true
                    text: (offset === 0 ? "Today · " : offset === 1 ? "Tomorrow · " : offset === -1 ? "Yesterday · " : "") + Qt.formatDate(popup.selected, "ddd, d MMMM")
                }

                // Day forecast
                Label {
                    readonly property var day: popup.forecast[Qt.formatDate(popup.selected, "yyyy-MM-dd")] ?? null
                    readonly property var info: day ? Weather.describe(day.code, false) : null

                    Layout.fillWidth: true
                    visible: !!day
                    text: day ? `${Theme.glyph(info[0])}  ${info[1]}  ·  ${day.max}° / ${day.min}°${day.rain ? `  ·  ${Theme.glyph(0xf058c)} ${day.rain}%` : ""}` : ""
                    font.pixelSize: 11
                    color: Theme.subtext0
                }

                HourlyStrip {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    weather: popup.cache.weather?.data ?? null
                    day: popup.selected
                }

                // Nothing connected yet
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: popup.sources.length === 0
                    spacing: 8

                    Label {
                        Layout.fillWidth: true
                        text: "Connect your Nextcloud or subscribe to a calendar to see your appointments."
                        color: Theme.overlay1
                        wrapMode: Text.Wrap
                    }
                    IconButton {
                        glyph: Theme.glyph(0xf0342) // 󰍂
                        text: "Set up"
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
                    visible: popup.sources.length > 0 && popup.dayEvents.length === 0
                    text: popup.syncing && !(popup.viewKey in (popup.cache.events ?? {})) ? "Loading appointments…" : "Nothing planned"
                    color: Theme.overlay0
                    font.italic: true
                }

                ListView {
                    id: eventList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                        colour: modelData.colour
                        editable: modelData.editable
                        onEditRequested: popup.editAppointment(modelData)
                        onDeleteRequested: popup.deleteEvent(modelData)
                    }
                }

                Item {
                    Layout.fillHeight: true
                    visible: !eventList.visible
                }
                Label {
                    Layout.fillWidth: true
                    visible: popup.writable.length > 0
                    text: "Double-click a day to add an appointment"
                    font.pixelSize: 10
                    color: Theme.overlay0
                }
            }
        }
    }

    // Settings view
    CalendarSettings {
        Layout.fillWidth: true
        visible: popup.editing
        location: popup.settings.location ?? null
        locationResults: popup.locationResults
        weekStart: popup.weekStart
        weekNumbers: popup.weekNumbers
        reminders: popup.settings.reminders ?? true
        nextcloud: popup.nextcloud
        subscriptions: popup.subscriptions
        prefill: popup.prefill
        busy: popup.accountBusy
        error: popup.accountError || popup.weatherError
        onSearchLocation: query => popup.searchLocation(query, false)
        onPickLocation: place => popup.pickLocation(place)
        onSetWeekStart: day => {
            popup.update({ weekStart: day });
            popup.fetchEvents();
        }
        onSetWeekNumbers: on => popup.update({ weekNumbers: on })
        onSetReminders: on => popup.update({ reminders: on })
        onSignIn: (url, user, password) => popup.signIn(url, user, password)
        onSignOut: popup.signOut()
        onRefreshCalendars: popup.refreshCalendars()
        onToggleCalendar: href => popup.toggleCalendar(href)
        onAddSubscription: (name, url) => popup.addSubscription(name, url)
        onToggleSubscription: id => popup.toggleSubscription(id)
        onRemoveSubscription: id => popup.removeSubscription(id)
    }
}
