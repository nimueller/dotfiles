import QtQuick
import Quickshell.Io

// One call of a helper that answers in JSON, {"error": "..."} on failure
// (calendar-dav.py, weather.py): run(args, input, done, failed) writes
// `input` to its stdin and calls done(result) or failed(error).
Process {
    id: call

    required property string helper
    property string input: ""
    property string failure: "The calendar helper failed" // when it answers no JSON
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
                result = {
                    error: call.failure
                };
            }
            if (result.error && call.failed) {
                call.failed(result.error);
            } else if (!result.error && call.done) {
                call.done(result);
            }
        }
    }
}
