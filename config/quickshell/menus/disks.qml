// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The partition editor, from the system menu and from Files' "Open with Disks"
// and "Format…" (disk-utility.py): a drive's partitions and free space, what
// can be done with each, and the plan of changes (Disks.qml, disks.py). Like
// fdisk, every change is only planned, with the drive shown as it will be;
// "Apply" writes the plan, after asking once more. Internal drives show under
// Advanced; what the running system uses stays locked (disk_objects.py).
Popup {
    id: root

    name: "disks"
    atLeft: true
    cardWidth: 540
    // polkit's password dialog and the file chooser take the focus
    keepOpen: Disks.applying || Disks.choosingImage

    property bool confirming: false

    // Steps without a form of their own: added to the plan right away
    readonly property var direct: ["delete", "check", "repair", "mount", "unmount", "lock"]
    readonly property var actionTitles: ({
            create: I18n.tr("New partition"),
            format: I18n.tr("Format"),
            delete: I18n.tr("Delete"),
            resize: I18n.tr("Resize"),
            label: I18n.tr("Label"),
            name: I18n.tr("Name"),
            type: I18n.tr("Type"),
            bootable: I18n.tr("Bootable"),
            check: I18n.tr("Check"),
            repair: I18n.tr("Repair"),
            mount: I18n.tr("Mount"),
            unmount: I18n.tr("Unmount"),
            unlock: I18n.tr("Unlock"),
            lock: I18n.tr("Lock"),
            passphrase: I18n.tr("Passphrase"),
            backup: I18n.tr("Save as image"),
            table: I18n.tr("New partition table"),
            erase: I18n.tr("Erase all"),
            restore: I18n.tr("Write image"),
            poweroff: I18n.tr("Power off")
        })
    readonly property var dangerous: ["delete", "format", "table", "erase", "restore"]

    Component.onCompleted: Disks.refresh()

    function act(action, segment) {
        if (action === "bootable") {
            Disks.add({
                op: "bootable",
                target: segment.id,
                on: !segment.bootable
            });
        } else if (direct.includes(action)) {
            Disks.add({
                op: action,
                target: segment.id
            });
        } else if (action === "backup") {
            Disks.chooseImage("save", path => Disks.add({
                    op: "backup",
                    target: segment.id,
                    image: path
                }));
        } else {
            Disks.form = action;
        }
    }

    function actDrive(action) {
        if (action === "poweroff") {
            Disks.add({
                op: "poweroff"
            });
        } else if (action === "restore") {
            Disks.chooseImage("open", (path, size) => Disks.add({
                    op: "restore",
                    image: path,
                    image_size: size
                }));
        } else if (action === "backup") {
            Disks.chooseImage("save", path => Disks.add({
                    op: "backup",
                    target: Disks.shown.block,
                    image: path
                }));
        } else {
            Disks.selected = "";
            Disks.form = action;
        }
    }

    function stateGlyph(index) {
        const glyphs = {
            running: 0xf0997 // 󰦗
            ,
            done: 0xf012c // 󰄬
            ,
            failed: 0xf0156 // 󰅖
        };
        const state = Disks.states[index] ?? "";
        return state ? Theme.glyph(glyphs[state]) : `${index + 1}.`;
    }

    function stateColor(index) {
        const colors = {
            running: Theme.sapphire,
            done: Theme.green,
            failed: Theme.red
        };
        return colors[Disks.states[index] ?? ""] ?? Theme.overlay1;
    }

    // The steps, while one is written: what it does and how far it got
    function stepNote(index) {
        const step = Disks.steps[index];
        if (step.problem) {
            return step.problem;
        }
        if (Disks.states[index] === "running" && Disks.progress >= 0) {
            return `${Math.round(Disks.progress * 100)} %`;
        }
        return Disks.notes[index] ?? "";
    }

    Connections {
        target: Disks

        function onStepsChanged() {
            root.confirming = false;
        }
    }

    Timer {
        id: confirmTimer
        interval: 6000
        onTriggered: root.confirming = false
    }

    // udisks' changes while the menu is open: a drive plugged in, mounted, …
    Process {
        command: [Disks.helper, "watch"]
        running: true
        stdout: SplitParser {
            onRead: Disks.refresh()
        }
    }

    Header {
        glyph: Theme.glyph(0xf02ca) // 󰋊
        title: I18n.tr("Drives")
        badge: Disks.steps.length && !Disks.finished ? I18n.tr("%1 planned", Disks.steps.length) : ""
        badgeColor: Theme.peach

        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            text: I18n.tr("Advanced")
            active: Disks.advanced
            onClicked: Disks.setAdvanced(!Disks.advanced)
        }
    }

    Label {
        Layout.fillWidth: true
        visible: Disks.visibleDrives.length === 0
        text: Disks.loaded ? I18n.tr("No removable drives. Internal ones show under Advanced.") : I18n.tr("Looking at the drives…")
        color: Theme.subtext0
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }

    // ---------- The drive ----------

    Dropdown {
        Layout.fillWidth: true
        visible: Disks.visibleDrives.length > 0
        // One plan per drive: apply or discard it first
        enabled: !Disks.steps.length && !Disks.applying
        model: Disks.visibleDrives.map(d => ({
                    text: `${d.name} · ${d.device}`,
                    value: d.id
                }))
        current: Disks.driveId
        onPicked: value => Disks.pickDrive(value)
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !!Disks.shown
        spacing: 6

        Label {
            Layout.fillWidth: true
            text: Disks.shown?.detail ?? ""
            color: Theme.subtext0
        }
        Label {
            Layout.fillWidth: true
            visible: !!Disks.shown?.inUse
            text: I18n.tr("Locked: %1", Disks.shown?.inUse ?? "")
            color: Theme.peach
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
        DiskBar {
            Layout.fillWidth: true
            Layout.topMargin: 4
            drive: Disks.shown
            selected: Disks.selected
            onPicked: id => Disks.select(id)
        }
    }

    Column {
        Layout.fillWidth: true
        visible: !!Disks.shown
        spacing: 2

        Repeater {
            model: Disks.shown?.segments ?? []

            delegate: Rectangle {
                id: row

                required property var modelData
                readonly property bool isSelected: modelData.id === Disks.selected

                width: parent.width
                implicitHeight: rowContent.implicitHeight + 10
                radius: 8
                color: isSelected || rowMouse.containsMouse ? Theme.surface0 : "transparent"

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Disks.select(row.modelData.id)
                }

                RowLayout {
                    id: rowContent

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Rectangle {
                        implicitWidth: 10
                        implicitHeight: 10
                        radius: 3
                        color: row.modelData.kind === "free" ? "transparent" : Disks.color(row.modelData)
                        border.width: 1
                        border.color: row.modelData.kind === "free" ? Theme.surface2 : "transparent"
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            width: parent.width
                            text: `${row.modelData.title} · ${row.modelData.sizeText}`
                            font.bold: true
                        }
                        Label {
                            width: parent.width
                            visible: !!row.modelData.detail
                            text: row.modelData.detail
                            color: Theme.overlay1
                            font.pixelSize: 11
                        }
                    }
                    Label {
                        visible: !!row.modelData.inUse || !!row.modelData.changed
                        text: row.modelData.inUse ? Theme.glyph(0xf033e) : I18n.tr("changed") // 󰌾
                        color: row.modelData.inUse ? Theme.overlay1 : Theme.peach
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // ---------- What can be done ----------

    Label {
        Layout.fillWidth: true
        visible: !!Disks.segment?.inUse
        text: I18n.tr("Locked: %1", Disks.segment?.inUse ?? "")
        color: Theme.peach
    }

    Flow {
        Layout.fillWidth: true
        visible: !Disks.form && (Disks.segment?.actions.length ?? 0) > 0
        spacing: 6

        Repeater {
            model: Disks.segment?.actions ?? []

            delegate: IconButton {
                required property string modelData

                text: root.actionTitles[modelData] ?? modelData
                accent: root.dangerous.includes(modelData) ? Theme.red : Theme.lavender
                active: root.dangerous.includes(modelData)
                onClicked: root.act(modelData, Disks.segment)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !Disks.form && (Disks.shown?.actions.length ?? 0) > 0
        spacing: 6

        SectionTitle {
            text: I18n.tr("Drive")
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: Disks.shown?.actions ?? []

                delegate: IconButton {
                    required property string modelData

                    text: root.actionTitles[modelData] ?? modelData
                    accent: root.dangerous.includes(modelData) ? Theme.red : Theme.lavender
                    active: root.dangerous.includes(modelData)
                    onClicked: root.actDrive(modelData)
                }
            }
        }
    }

    Loader {
        Layout.fillWidth: true
        active: !!Disks.form
        visible: active

        sourceComponent: DiskForm {
            action: Disks.form
            segment: Disks.segment
            drive: Disks.shown
        }
    }

    // ---------- The plan ----------

    SectionTitle {
        visible: Disks.steps.length > 0
        text: Disks.finished ? I18n.tr("Written") : I18n.tr("Planned, not written yet")
    }

    Column {
        Layout.fillWidth: true
        visible: Disks.steps.length > 0
        spacing: 4

        Repeater {
            model: Disks.steps

            delegate: RowLayout {
                id: stepRow

                required property var modelData
                required property int index

                width: parent.width
                spacing: 8

                Label {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 18
                    text: root.stateGlyph(stepRow.index)
                    color: root.stateColor(stepRow.index)
                }
                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Label {
                        width: parent.width
                        text: stepRow.modelData.text
                        color: stepRow.modelData.step.auto ? Theme.subtext0 : Theme.text
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        text: root.stepNote(stepRow.index)
                        color: stepRow.modelData.problem ? Theme.red : Theme.overlay1
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !!Disks.error
        text: Disks.error
        color: Theme.red
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }

    Label {
        Layout.fillWidth: true
        visible: root.confirming
        text: I18n.tr("Write %1 changes to %2 (%3)? What they delete or overwrite can't be brought back.", Disks.steps.length, Disks.drive?.name ?? "", Disks.sizeText(Disks.drive?.size ?? 0))
        color: Theme.peach
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }

    Label {
        Layout.fillWidth: true
        visible: Disks.applying
        text: I18n.tr("Writing… Leave the drive connected until it's done.")
        color: Theme.sapphire
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6

        IconButton {
            visible: Disks.steps.length > 0 && !Disks.applying && !Disks.finished
            glyph: Theme.glyph(0xf054c) // 󰕌
            text: I18n.tr("Undo")
            onClicked: Disks.undo()
        }
        IconButton {
            visible: Disks.steps.length > 0 && !Disks.applying && !Disks.finished
            text: I18n.tr("Discard")
            onClicked: Disks.discard()
        }
        Item {
            Layout.fillWidth: true
        }
        IconButton {
            text: I18n.tr("Close")
            onClicked: root.close()
        }
        IconButton {
            visible: Disks.finished
            text: I18n.tr("Done")
            active: true
            onClicked: Disks.discard()
        }
        IconButton {
            visible: Disks.steps.length > 0 && !Disks.applying && !Disks.finished
            glyph: Theme.glyph(0xf0193) // 󰆓
            text: root.confirming ? I18n.tr("Write changes") : I18n.tr("Apply (%1)", Disks.steps.length)
            accent: root.confirming ? Theme.red : Theme.green
            active: !Disks.hasProblems
            opacity: Disks.hasProblems ? 0.5 : 1
            onClicked: {
                if (Disks.hasProblems || Disks.busy) {
                    return;
                }
                if (root.confirming) {
                    root.confirming = false;
                    Disks.apply();
                } else {
                    root.confirming = true;
                    confirmTimer.restart();
                }
            }
        }
    }
}
