// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The partition editor, a window of its own: from the system menu, with
// `toggle.sh disks`, and from Files' "Open with Disks" and "Format…"
// (disk-utility.py). The drives on the left, the picked one's partitions and
// free space with what can be done with each in the middle, the plan on the
// right (Disks.qml, disks.py). Like fdisk, every change is only planned, with
// the drive shown as it will be; "Apply" writes the plan, after asking once
// more. Internal drives show under Advanced; what the running system uses
// stays locked (disk_objects.py).
ShellRoot {
    id: root

    property bool confirming: false

    // Steps without a form of their own: added to the plan right away
    readonly property var direct: ["delete", "check", "repair", "mount", "unmount", "lock"]
    readonly property var dangerous: ["delete", "format", "table", "erase", "restore"]
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

    Component.onCompleted: Disks.refresh()

    function close() {
        Menus.close("disks");
    }

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

    // Why a step can't be done, how far it got, or what it found
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

    function confirmText() {
        const drive = Disks.drive;
        const size = Disks.sizeText(drive?.size ?? 0);
        return I18n.tr("Write %1 changes to %2 (%3)? What they delete or overwrite can't be brought back.", Disks.steps.length, drive?.name ?? "", size);
    }

    function applyClicked() {
        if (Disks.hasProblems || Disks.busy) {
            return;
        }
        if (confirming) {
            confirming = false;
            Disks.apply();
            return;
        }
        confirming = true;
        confirmTimer.restart();
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

    // udisks' changes while the window is open: a drive plugged in, mounted, …
    Process {
        command: [Disks.helper, "watch"]
        running: true
        stdout: SplitParser {
            onRead: Disks.refresh()
        }
    }

    FloatingWindow {
        title: I18n.tr("Drives")
        implicitWidth: 1000
        implicitHeight: 660
        color: Theme.base
        onVisibleChanged: if (!visible) {
            root.close();
        }

        WindowClose {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            z: 1
            onClicked: root.close()
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---------- The drives ----------

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 230
                color: Theme.mantle

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Header {
                        Layout.bottomMargin: 10
                        glyph: Theme.glyph(0xf02ca) // 󰋊
                        title: I18n.tr("Drives")
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: Disks.visibleDrives.length === 0
                        text: Disks.loaded ? I18n.tr("No removable drives. Internal ones show under Advanced.") : I18n.tr("Looking at the drives…")
                        color: Theme.subtext0
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }

                    Repeater {
                        model: Disks.visibleDrives

                        delegate: DriveRow {}
                    }

                    // One plan per drive: apply or discard it first
                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: Disks.steps.length > 0 && !Disks.finished
                        text: I18n.tr("Apply or discard the plan to switch drives")
                        color: Theme.overlay1
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Column {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                width: parent.width
                                text: I18n.tr("Advanced")
                            }
                            Label {
                                width: parent.width
                                text: I18n.tr("Internal drives too")
                                color: Theme.overlay1
                                font.pixelSize: 11
                            }
                        }
                        Switch {
                            checked: Disks.advanced
                            accent: Theme.peach
                            onToggled: Disks.setAdvanced(!Disks.advanced)
                        }
                    }
                }
            }

            // ---------- The picked drive ----------

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: page.implicitHeight + 40
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: page

                    x: 20
                    y: 16
                    width: parent.width - 40
                    spacing: 12

                    Label {
                        Layout.fillWidth: true
                        visible: !!Disks.shown
                        text: Disks.shown ? `${Disks.shown.name} · ${Disks.shown.device}` : ""
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: -8
                        visible: !!Disks.shown
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
                        visible: !!Disks.shown
                        drive: Disks.shown
                        selected: Disks.selected
                        onPicked: id => Disks.select(id)
                    }

                    Column {
                        Layout.fillWidth: true
                        visible: !!Disks.shown
                        spacing: 2

                        Repeater {
                            model: Disks.shown?.segments ?? []

                            delegate: SegmentRow {}
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: !!Disks.segment?.inUse
                        text: I18n.tr("Locked: %1", Disks.segment?.inUse ?? "")
                        color: Theme.peach
                    }

                    ActionRow {
                        visible: !Disks.form && (Disks.segment?.actions.length ?? 0) > 0
                        title: Disks.segment?.title ?? ""
                        actions: Disks.segment?.actions ?? []
                        onActed: action => root.act(action, Disks.segment)
                    }

                    ActionRow {
                        visible: !Disks.form && (Disks.shown?.actions.length ?? 0) > 0
                        title: I18n.tr("Drive")
                        actions: Disks.shown?.actions ?? []
                        onActed: action => root.actDrive(action)
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: !!Disks.form
                        visible: active

                        sourceComponent: DiskForm {
                            // The Loader doesn't pass its width on
                            width: page.width
                            action: Disks.form
                            segment: Disks.segment
                            drive: Disks.shown
                        }
                    }
                }
            }

            // ---------- The plan ----------

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 320
                color: Theme.mantle

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.topMargin: 36
                    spacing: 10

                    SectionTitle {
                        text: Disks.finished ? I18n.tr("Written") : I18n.tr("Planned, not written yet")
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: Disks.steps.length === 0
                        text: I18n.tr("Nothing planned. Pick a partition or free space and an action; nothing is written before Apply.")
                        color: Theme.overlay1
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: stepList.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        Column {
                            id: stepList

                            width: parent.width
                            spacing: 8

                            Repeater {
                                model: Disks.steps

                                delegate: StepRow {}
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
                        text: root.confirmText()
                        color: Theme.peach
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: Disks.applying
                        text: I18n.tr("Writing… Leave the drive connected until it's done.")
                        color: Theme.sapphire
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }

                    RowLayout {
                        Layout.fillWidth: true
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
                            onClicked: root.applyClicked()
                        }
                    }
                }
            }
        }
    }

    // A drive in the list on the left
    component DriveRow: Rectangle {
        id: driveRow

        required property var modelData
        readonly property bool isPicked: modelData.id === Disks.driveId

        Layout.fillWidth: true
        implicitHeight: driveColumn.implicitHeight + 12
        radius: 8
        color: isPicked || driveMouse.containsMouse ? Theme.surface0 : "transparent"

        Column {
            id: driveColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 10
            spacing: 1

            Label {
                width: parent.width
                text: driveRow.modelData.name
                color: driveRow.isPicked ? Theme.blue : Theme.text
                font.bold: driveRow.isPicked
            }
            Label {
                width: parent.width
                text: `${driveRow.modelData.device} · ${Disks.sizeText(driveRow.modelData.size)}`
                color: Theme.overlay1
                font.pixelSize: 11
            }
        }

        MouseArea {
            id: driveMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Disks.pickDrive(driveRow.modelData.id)
        }
    }

    // A partition or free space, under the bar
    component SegmentRow: Rectangle {
        id: row

        required property var modelData
        readonly property bool isSelected: modelData.id === Disks.selected
        readonly property bool isFree: modelData.kind === "free"

        width: parent.width
        implicitHeight: rowContent.implicitHeight + 12
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
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                implicitWidth: 12
                implicitHeight: 12
                radius: 3
                color: row.isFree ? "transparent" : Disks.color(row.modelData)
                border.width: row.isFree ? 1 : 0
                border.color: Theme.surface2
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
                visible: !!row.modelData.inUse
                text: Theme.glyph(0xf033e) // 󰌾
                color: Theme.overlay1
            }
            Label {
                visible: !row.modelData.inUse && !!row.modelData.changed
                text: I18n.tr("changed")
                color: Theme.peach
                font.pixelSize: 11
            }
        }
    }

    // What can be done with a partition, or with the whole drive
    component ActionRow: ColumnLayout {
        id: actionRow

        property string title
        property var actions: []
        signal acted(string action)

        Layout.fillWidth: true
        spacing: 6

        SectionTitle {
            text: actionRow.title
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: actionRow.actions

                delegate: IconButton {
                    required property string modelData

                    text: root.actionTitles[modelData] ?? modelData
                    accent: root.dangerous.includes(modelData) ? Theme.red : Theme.lavender
                    active: root.dangerous.includes(modelData)
                    onClicked: actionRow.acted(modelData)
                }
            }
        }
    }

    // A step of the plan: what it does, and why it can't or how it went
    component StepRow: RowLayout {
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
