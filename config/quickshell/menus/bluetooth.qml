// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// Bluetooth menu for the bar's Bluetooth module, on top of BlueZ: switch it
// on and off, the paired devices (connect, disconnect, forget, their
// battery) and, while the menu is open, the devices nearby to pair with.
// There's no pairing agent here, so devices that show or ask for a code
// (keyboards) pair in Blueman, the gear; headphones, mice and speakers
// pair right here.
Popup {
    id: popup

    name: "bluetooth"

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property var devices: adapter?.devices.values ?? []
    // Paired ones: connected first, then by name
    readonly property var paired: devices.filter(d => d.paired || d.bonded).sort((a, b) => b.connected - a.connected || a.name.localeCompare(b.name))
    // Nearby ones that say their name (BlueZ names the others after their address)
    readonly property var nearby: devices.filter(d => !d.paired && !d.bonded && d.name && d.name !== d.address.replace(/:/g, "-")).sort((a, b) => a.name.localeCompare(b.name))
    property string expanded: "" // address of the device with its details open
    property var trying: ({}) // address → "pair" | "connect", asked for here
    property var errors: ({}) // address → why it didn't work

    function mark(map, address, value) {
        const m = Object.assign({}, map);
        if (value)
            m[address] = value;
        else
            delete m[address];
        return m;
    }

    function activate(d) {
        errors = mark(errors, d.address, "");
        if (!d.paired && !d.bonded) {
            trying = mark(trying, d.address, "pair");
            d.pair();
        } else if (d.connected) {
            d.disconnect();
        } else {
            trying = mark(trying, d.address, "connect");
            d.connect();
        }
    }

    // What became of a pairing or connection asked for here. Per device
    // here rather than in the rows, which the lists recreate as they change.
    Instantiator {
        model: popup.devices

        delegate: Connections {
            id: watch

            required property var modelData

            target: modelData

            // Paired: trusted, so it connects again by itself, then connected
            function onPairedChanged() {
                if (modelData.paired && popup.trying[modelData.address] === "pair") {
                    modelData.trusted = true;
                    popup.trying = popup.mark(popup.trying, modelData.address, "connect");
                    modelData.connect();
                }
            }
            // Paired changes around the same time; look a moment later
            function onPairingChanged() {
                if (!modelData.pairing && popup.trying[modelData.address] === "pair")
                    pairCheck.restart();
            }
            function onStateChanged() {
                const address = modelData.address;
                if (modelData.connected) {
                    popup.trying = popup.mark(popup.trying, address, "");
                } else if (popup.trying[address] === "connect" && modelData.state === BluetoothDeviceState.Disconnected) {
                    popup.trying = popup.mark(popup.trying, address, "");
                    popup.errors = popup.mark(popup.errors, address, "Couldn't connect. Is it switched on and in reach?");
                }
            }

            property Timer pairCheck: Timer {
                interval: 1000
                onTriggered: {
                    const d = watch.modelData;
                    if (!d.paired && !d.bonded && !d.pairing && popup.trying[d.address] === "pair") {
                        popup.trying = popup.mark(popup.trying, d.address, "");
                        popup.errors = popup.mark(popup.errors, d.address, "Pairing didn't work. Devices that show or ask for a code (keyboards) pair in Blueman, the gear.");
                    }
                }
            }
        }
    }

    // Look for devices while the menu is open; BlueZ stops when this
    // instance quits
    Binding {
        when: popup.on
        target: popup.adapter
        property: "discovering"
        value: true
    }

    Header {
        glyph: Theme.glyph(0xf00af) // 󰂯
        accent: Theme.blue
        title: "Bluetooth"
        badge: popup.on && popup.adapter.discovering ? "Searching" : ""

        Switch {
            visible: !!popup.adapter
            checked: popup.on
            accent: Theme.blue
            onToggled: popup.adapter.enabled = !popup.on
        }
        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            onClicked: {
                Quickshell.execDetached(["blueman-manager"]);
                popup.close();
            }
        }
    }

    Label {
        visible: !popup.adapter
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        text: "BlueZ doesn't see a Bluetooth adapter: the Bluetooth service isn't running, or the controller has no address of its own (Surface Pro X). system/setup.sh sets up both."
        color: Theme.subtext0
    }
    Label {
        visible: !!popup.adapter && !popup.on
        text: popup.adapter?.state === BluetoothAdapterState.Blocked ? "Blocked by a key or switch (airplane mode)" : "Bluetooth is off"
        color: Theme.overlay0
        font.italic: true
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: popup.on
        spacing: 8

        SectionTitle {
            text: "Devices"
        }
        Label {
            visible: popup.paired.length === 0
            text: "No paired devices yet"
            color: Theme.overlay0
            font.italic: true
        }

        Repeater {
            model: popup.paired

            delegate: BluetoothRow {
                required property var modelData

                Layout.fillWidth: true
                device: modelData
                expanded: popup.expanded === modelData.address
                error: popup.errors[modelData.address] ?? ""
                onActivated: popup.activate(modelData)
                onToggleExpanded: popup.expanded = expanded ? "" : modelData.address
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: popup.on
        spacing: 8

        SectionTitle {
            text: "Nearby — click to pair"
        }
        Label {
            visible: popup.nearby.length === 0
            text: "Looking for devices… Put the device into pairing mode."
            color: Theme.overlay0
            font.italic: true
        }

        ListView {
            id: nearbyList

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 240)
            visible: popup.nearby.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: popup.nearby

            delegate: BluetoothRow {
                required property var modelData

                width: nearbyList.width
                device: modelData
                error: popup.errors[modelData.address] ?? ""
                onActivated: popup.activate(modelData)
            }
        }
    }
}
