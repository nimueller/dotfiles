import QtQuick
import Quickshell.Io

// One call of calendar-dav.py: run(args, input, done, failed) writes `input`
// to its stdin and calls done(result) or failed(error) with its JSON answer.
Process {
    id: call

    required property string helper
    property string input: ""
    property var done: null
    property var failed: null

    function run(args, input, done, failed) {
        call.input = input ?? "";
        call.done = done;
        call.failed = failed;
        stdinEnabled = !!call.input;
        command = [helper, ...args];
        running = true;
    }

    onStarted: {
        if (input) {
            write(input);
            stdinEnabled = false;
        }
    }
    stdout: StdioCollector {
        onStreamFinished: {
            let result;
            try {
                result = JSON.parse(text);
            } catch (e) {
                result = { error: "The calendar helper failed" };
            }
            if (result.error && call.failed)
                call.failed(result.error);
            else if (!result.error && call.done)
                call.done(result);
        }
    }
}
