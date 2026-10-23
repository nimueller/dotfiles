pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The pairing agent (bluetooth-agent.py) in the daemon, running all the time:
// BlueZ asks it for codes and permissions whenever a pairing or connection
// needs someone, also with the Bluetooth menu closed; a question opens it
// (bluetooth.qml shows them as BluetoothRequest cards).
Singleton {
    id: root

    // The open questions, oldest first: {id, kind, address, name, code,
    // entered, service} (see bluetooth-agent.py)
    property var requests: []

    function answer(id, ok, value) {
        requests = requests.filter(r => r.id !== id);
        send({ id: id, ok: ok, value: value ?? "" });
    }

    // Be the agent BlueZ asks again, after Blueman's took over
    function makeDefault() {
        send({ default: true });
    }

    function send(message) {
        if (agent.running)
            agent.write(JSON.stringify(message) + "\n");
    }

    function received(message) {
        if (message.done !== undefined) {
            requests = requests.filter(r => r.id !== message.done);
            return;
        }
        const i = requests.findIndex(r => r.id === message.id);
        if (i >= 0) {
            // A shown code, with another key typed on the device
            const next = requests.slice();
            next[i] = message;
            requests = next;
            return;
        }
        requests = requests.concat([message]);
        if (!Menus.isOpen("bluetooth"))
            Menus.toggle("bluetooth");
    }

    Process {
        id: agent

        // Only in the daemon: a menu tried out on its own doesn't take over
        running: Menus.hosted
        stdinEnabled: true
        command: ["/usr/bin/python3", Quickshell.shellPath("bluetooth-agent.py")]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.received(JSON.parse(line));
                } catch (e) {
                    console.warn("bluetooth-agent:", line);
                }
            }
        }
        onExited: {
            root.requests = [];
            if (Menus.hosted)
                restart.start();
        }
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: agent.running = Menus.hosted
    }
}
