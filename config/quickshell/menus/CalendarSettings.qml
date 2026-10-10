import QtQuick
import QtQuick.Layouts

// Settings view of the calendar menu. Left: weather location and how weeks
// are shown. Right: the Nextcloud account with its calendars, and read-only
// ICS subscriptions (holidays etc.).
RowLayout {
    id: root

    property var location: null // { name, lat, lon }
    property var locationResults: []
    property int weekStart: 1
    property bool weekNumbers: true
    property var nextcloud: null // { url, user, calendars: [{ href, name, color, enabled, writable }] }
    property var subscriptions: [] // [{ id, name, url, color, enabled }]
    property var prefill: ({}) // { url, user } from the Nextcloud desktop client
    property bool busy: false
    property string error: ""

    signal searchLocation(string query)
    signal pickLocation(var place)
    signal setWeekStart(int day)
    signal setWeekNumbers(bool on)
    signal signIn(string url, string user, string password)
    signal signOut
    signal refreshCalendars
    signal toggleCalendar(string href)
    signal addSubscription(string name, string url)
    signal toggleSubscription(string id)
    signal removeSubscription(string id)

    spacing: 24

    // Left column ---------------------------------------------------------------
    ColumnLayout {
        Layout.preferredWidth: 380
        Layout.alignment: Qt.AlignTop
        spacing: 10

        SectionTitle {
            text: "Weather location"
        }
        Label {
            Layout.fillWidth: true
            text: root.location ? `${Theme.glyph(0xf034e)}  ${root.location.name}` : "No location set" // 󰍎
            color: root.location ? Theme.text : Theme.overlay0
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            InputField {
                id: city
                Layout.fillWidth: true
                placeholder: "Search a city"
                accent: Theme.lavender
                onAccepted: if (text) root.searchLocation(text)
            }
            IconButton {
                glyph: Theme.glyph(0xf0349) // 󰍉
                text: "Search"
                onClicked: if (city.text) root.searchLocation(city.text)
            }
        }
        Repeater {
            model: root.locationResults

            delegate: Rectangle {
                id: place

                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 28
                radius: 8
                color: placeMouse.containsMouse ? Theme.alpha(Theme.lavender, 0.14) : "transparent"

                Label {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    text: [place.modelData.name, place.modelData.admin1, place.modelData.country].filter(x => x).join(", ")
                    color: placeMouse.containsMouse ? Theme.lavender : Theme.subtext1
                }
                MouseArea {
                    id: placeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        city.text = "";
                        root.pickLocation(place.modelData);
                    }
                }
            }
        }

        SectionTitle {
            Layout.topMargin: 8
            text: "Weeks"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label {
                Layout.fillWidth: true
                text: "Start on"
                color: Theme.subtext1
            }
            Repeater {
                model: [[1, "Monday"], [0, "Sunday"], [6, "Saturday"]]

                delegate: IconButton {
                    required property var modelData

                    text: modelData[1]
                    accent: Theme.mauve
                    active: root.weekStart === modelData[0]
                    onClicked: root.setWeekStart(modelData[0])
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: "Show week numbers"
                color: Theme.subtext1
            }
            Switch {
                checked: root.weekNumbers
                accent: Theme.mauve
                onToggled: root.setWeekNumbers(!root.weekNumbers)
            }
        }
    }

    Rectangle {
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Theme.surface0
    }

    // Right column --------------------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 10

        SectionTitle {
            text: "Nextcloud"
        }

        // Signed out: sign-in form
        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.nextcloud
            spacing: 6

            InputField {
                id: url
                Layout.fillWidth: true
                placeholder: "Server, e.g. https://cloud.example.com"
                accent: Theme.blue
                text: root.prefill.url ?? ""
            }
            InputField {
                id: user
                Layout.fillWidth: true
                placeholder: "Username"
                accent: Theme.blue
                text: root.prefill.user ?? ""
            }
            InputField {
                id: password
                Layout.fillWidth: true
                placeholder: "App password"
                masked: true
                accent: Theme.blue
                onAccepted: signInButton.clicked()
            }
            Label {
                Layout.fillWidth: true
                text: "Create an app password in Nextcloud under Personal settings → Security. It is kept in your keyring."
                font.pixelSize: 10
                color: Theme.overlay1
                wrapMode: Text.Wrap
            }
            IconButton {
                id: signInButton
                glyph: Theme.glyph(0xf0342) // 󰍂
                text: root.busy ? "Signing in…" : "Sign in"
                accent: Theme.blue
                active: true
                onClicked: {
                    if (!root.busy && url.text && user.text && password.text)
                        root.signIn(url.text, user.text, password.text);
                }
            }
        }

        // Signed in: account and calendars
        ColumnLayout {
            Layout.fillWidth: true
            visible: !!root.nextcloud
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    Layout.fillWidth: true
                    text: root.nextcloud ? `${root.nextcloud.user} on ${root.nextcloud.url.replace(/^https?:\/\//, "")}` : ""
                    color: Theme.subtext1
                }
                IconButton {
                    glyph: Theme.glyph(0xf0450) // 󰑐
                    text: root.busy ? "Loading…" : "Reload"
                    onClicked: if (!root.busy) root.refreshCalendars()
                }
                IconButton {
                    glyph: Theme.glyph(0xf0343) // 󰍃
                    text: "Sign out"
                    accent: Theme.red
                    onClicked: root.signOut()
                }
            }

            Repeater {
                model: root.nextcloud?.calendars ?? []

                delegate: CalendarToggle {
                    required property var modelData

                    Layout.fillWidth: true
                    name: modelData.name
                    colour: modelData.color
                    detail: modelData.writable === false ? "read-only" : ""
                    checked: modelData.enabled
                    onToggled: root.toggleCalendar(modelData.href)
                }
            }
        }

        SectionTitle {
            Layout.topMargin: 8
            text: "Subscriptions (read-only ICS)"
        }

        Repeater {
            model: root.subscriptions

            delegate: CalendarToggle {
                required property var modelData

                Layout.fillWidth: true
                name: modelData.name
                colour: modelData.color
                detail: modelData.url.replace(/^(https?|webcal):\/\//, "")
                checked: modelData.enabled
                removable: true
                onToggled: root.toggleSubscription(modelData.id)
                onRemoved: root.removeSubscription(modelData.id)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            InputField {
                id: subName
                Layout.preferredWidth: 130
                placeholder: "Name"
                accent: Theme.teal
            }
            InputField {
                id: subUrl
                Layout.fillWidth: true
                placeholder: "https:// or webcal:// address of an .ics"
                accent: Theme.teal
                onAccepted: addButton.clicked()
            }
            IconButton {
                id: addButton
                glyph: Theme.glyph(0xf0415) // 󰐕
                text: "Add"
                onClicked: {
                    if (!subUrl.text.trim())
                        return;
                    root.addSubscription(subName.text.trim() || "Subscription", subUrl.text.trim());
                    subName.text = "";
                    subUrl.text = "";
                }
            }
        }
        Label {
            Layout.fillWidth: true
            text: "For example public holidays: most calendar sites offer an ICS link."
            font.pixelSize: 10
            color: Theme.overlay1
            wrapMode: Text.Wrap
        }

        Label {
            Layout.fillWidth: true
            visible: !!root.error
            text: root.error
            font.pixelSize: 10
            color: Theme.red
            wrapMode: Text.Wrap
        }
    }
}
