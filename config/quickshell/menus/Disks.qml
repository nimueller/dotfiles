pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The partition editor's state (disks.qml, disks.py): the drives, the plan for
// one of them and how far writing it got. Like fdisk, nothing touches a drive
// before apply(): every change is a step of the plan first, shown with what
// the drive will look like after it. Here and not in the menu, so writing
// goes on after the menu closes.
Singleton {
    id: root

    property var drives: [] // as `disks.py list` describes them
    property var filesystems: []
    property var types: ({}) // partition types by table: { gpt: [{ id, title }], dos: [...] }
    property bool loaded: false
    property string error: ""

    // Internal drives too, not only removable ones; off whenever the window opens
    property bool advanced: false
    property string driveId: ""
    property string selected: "" // the segment (partition, free space) picked
    property string form: "" // the action whose form is open, e.g. "create"

    property var steps: [] // [{ step, text, problem }]
    property var planned: null // the drive as the steps leave it
    property string revision: "" // the drive's when the plan was started
    property bool planning: false

    property bool applying: false
    property bool finished: false // the plan was written (or failed), its results are shown
    property var states: [] // per step: "", "running", "done", "failed"
    property var notes: [] // per step: what it found, e.g. a mount point
    property real progress: -1 // of the running step, -1 without

    property bool choosingImage: false
    // From Files' "Open with Drives" on an image: { path, size }, written to
    // the drive picked next with writeOffered()
    property var offered: null

    // From Files (disk-utility.py): show this device, maybe with the format form
    property string wanted: ""
    property bool wantFormat: false

    readonly property var visibleDrives: drives.filter(d => advanced || d.removable || d.id === driveId)
    readonly property var drive: drives.find(d => d.id === driveId) ?? null
    readonly property var shown: planned ?? drive // what the menu draws
    readonly property var segment: shown?.segments.find(s => s.id === selected) ?? null
    readonly property bool hasProblems: steps.some(s => !!s.problem)
    readonly property bool busy: applying || planning || choosingImage

    readonly property string helper: Quickshell.shellPath("disks.py")

    // ---------- Sizes ----------

    // Decimal units, as disk_layout.py writes them
    function sizeText(bytes) {
        const units = [["TB", 1e12], ["GB", 1e9], ["MB", 1e6], ["kB", 1e3]];
        for (const [unit, factor] of units) {
            if (bytes >= factor) {
                const value = bytes / factor;
                return `${value.toFixed(value >= 100 ? 0 : 1)} ${unit}`;
            }
        }
        return `${bytes} B`;
    }

    // "8 GB", "500M", "1,5 TB", "4 GiB" in bytes; a number alone is GB; -1 if it's none
    function parseSize(text) {
        const match = text.trim().match(/^([\d]+(?:[.,]\d+)?)\s*([kKMGT]?)(i?)B?$/);
        if (!match) {
            return -1;
        }
        const number = parseFloat(match[1].replace(",", "."));
        const exponent = {
            "": 3,
            "k": 1,
            "K": 1,
            "M": 2,
            "G": 3,
            "T": 4
        }[match[2]];
        const base = match[3] ? 1024 : 1000;
        return Math.round(number * Math.pow(base, exponent));
    }

    // A segment's colour, by its filesystem; encrypted ones all alike
    function color(segment) {
        if (segment.kind === "free") {
            return Theme.surface0;
        }
        if (segment.encrypted) {
            return Theme.lavender;
        }
        const colors = {
            ext2: Theme.blue,
            ext3: Theme.blue,
            ext4: Theme.blue,
            btrfs: Theme.teal,
            xfs: Theme.sapphire,
            f2fs: Theme.green,
            exfat: Theme.yellow,
            vfat: Theme.peach,
            ntfs: Theme.mauve,
            swap: Theme.red,
            crypto_LUKS: Theme.lavender,
            BitLocker: Theme.lavender
        };
        return colors[segment.fs] ?? Theme.overlay0;
    }

    // ---------- Reading ----------

    function refresh() {
        lister.run(["list"], "", result => root.listed(result), message => root.error = message);
    }

    function listed(result) {
        drives = result.drives;
        filesystems = result.filesystems;
        types = result.types;
        loaded = true;
        if (wanted) {
            showWanted();
        }
        if (!drive) {
            if (steps.length && !applying) {
                discard();
                error = I18n.tr("The drive is gone, so the plan was discarded");
            }
            pickDrive(visibleDrives[0]?.id ?? "");
            return;
        }
        if (steps.length && !applying && !finished && drive.revision !== revision) {
            discard();
            error = I18n.tr("The drive changed, so the plan was discarded");
        }
        if (!steps.length && !finished) {
            revision = drive.revision;
        }
    }

    // Files asked for a partition or a drive by its device
    function showWanted() {
        const name = wanted.replace("/dev/", "");
        const owner = drives.find(d => d.device === wanted || d.segments.some(s => s.title === name));
        wanted = "";
        if (!owner || steps.length) {
            return;
        }
        if (!owner.removable) {
            advanced = true;
        }
        pickDrive(owner.id);
        const part = owner.segments.find(s => s.title === name);
        selected = part?.id ?? (owner.segments.length === 1 ? owner.segments[0].id : "");
        form = wantFormat && segment?.actions.includes("format") ? "format" : "";
    }

    function open(device, format) {
        wanted = device;
        wantFormat = format;
        refresh();
        Menus.open("disks");
    }

    function select(id) {
        selected = id;
        form = "";
    }

    // Without it, only removable drives show: back to one of them
    function setAdvanced(on) {
        advanced = on;
        if (!on && drive && !drive.removable && !steps.length && !applying) {
            const removable = drives.find(d => d.removable);
            pickDrive(removable?.id ?? "");
        }
    }

    function pickDrive(id) {
        if (steps.length || applying) {
            return;
        }
        driveId = id;
        selected = "";
        form = "";
        finished = false;
        planned = null;
        revision = drive?.revision ?? "";
    }

    // ---------- Planning ----------

    function request(steps) {
        return {
            drive: driveId,
            revision: revision,
            steps: steps.map(s => s.step)
        };
    }

    // One step or several, e.g. a new partition table with one partition
    function add(added) {
        const r = request(steps);
        r.add = Array.isArray(added) ? added : [added];
        plan(r);
    }

    function plan(r) {
        if (busy) {
            return;
        }
        if (finished) {
            // A new plan, for the drive as the last one left it
            r.steps = r.steps.slice(steps.length);
            discard();
            r.revision = revision;
        }
        error = "";
        planning = true;
        planner.run(["plan"], JSON.stringify(r), result => root.takePlan(result), message => {
            root.planning = false;
            root.error = message;
        });
    }

    function takePlan(result) {
        planning = false;
        if (result.stale) {
            discard();
            error = I18n.tr("The drive changed, so the plan was discarded");
            refresh();
            return;
        }
        steps = result.steps;
        planned = steps.length ? result.drive : null;
        form = "";
        if (!shown?.segments.some(s => s.id === selected)) {
            selected = "";
        }
    }

    // The last step, with the unmount and lock steps put in for it
    function undo() {
        const kept = steps.slice(0, -1);
        while (kept.length && kept[kept.length - 1].step.auto) {
            kept.pop();
        }
        if (kept.length) {
            plan(request(kept));
        } else {
            discard();
        }
    }

    function discard() {
        steps = [];
        planned = null;
        form = "";
        finished = false;
        states = [];
        notes = [];
        revision = drive?.revision ?? "";
    }

    // ---------- Writing ----------

    function apply() {
        if (busy || !steps.length || hasProblems) {
            return;
        }
        error = "";
        applying = true;
        states = steps.map(() => "");
        notes = steps.map(() => "");
        progress = -1;
        writer.input = JSON.stringify(request(steps));
        writer.running = true;
    }

    function setAt(list, index, value) {
        const copy = list.slice();
        copy[index] = value;
        return copy;
    }

    function written(line) {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (event.stale) {
            error = I18n.tr("The drive changed, nothing was written");
        } else if (event.error) {
            error = event.error;
            if (event.step !== undefined) {
                states = setAt(states, event.step, "failed");
            }
        } else if (event.progress !== undefined) {
            progress = event.progress;
        } else if (event.state === "running") {
            states = setAt(states, event.step, "running");
            progress = -1;
        } else if (event.state === "done") {
            states = setAt(states, event.step, "done");
            notes = setAt(notes, event.step, event.note);
        }
    }

    function writtenAll() {
        applying = false;
        finished = true;
        planned = null;
        progress = -1;
        refresh();
    }

    // ---------- Images ----------

    // The file chooser, then picked(path, size)
    function chooseImage(mode, picked) {
        if (busy) {
            return;
        }
        choosingImage = true;
        chooser.run(["image", mode], "", result => {
            root.choosingImage = false;
            if (result.path) {
                picked(result.path, result.size);
            }
        }, message => {
            root.choosingImage = false;
            root.error = message;
        });
    }

    // Files' "Open with Drives" on an image (daemon.qml): the window, with the
    // image waiting for a drive. Still only a step of the plan once written.
    function offerImage(path) {
        offered = null;
        error = "";
        chooser.run(["image", "open", path], "", result => {
            if (result.path) {
                root.offered = result;
            }
        }, message => root.error = message);
        refresh();
        Menus.open("disks");
    }

    function writeOffered() {
        if (!offered || !shown?.actions.includes("restore")) {
            return;
        }
        add({
            op: "restore",
            image: offered.path,
            image_size: offered.size
        });
        offered = null;
    }

    HelperCall {
        id: lister
        helper: root.helper
        failure: I18n.tr("Couldn't read the drives")
    }

    HelperCall {
        id: planner
        helper: root.helper
        failure: I18n.tr("Couldn't plan the change")
    }

    HelperCall {
        id: chooser
        helper: root.helper
        failure: I18n.tr("Couldn't open the file chooser")
    }

    Process {
        id: writer

        property string input: ""

        command: [root.helper, "apply"]
        stdinEnabled: true
        onStarted: {
            write(input);
            stdinEnabled = false;
        }
        onExited: {
            stdinEnabled = true;
            root.writtenAll();
        }
        stdout: SplitParser {
            onRead: line => root.written(line)
        }
    }
}
