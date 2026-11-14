import QtQuick
import QtQuick.Layouts

// The form of one action of the partition editor (disks.qml): what a new
// partition, a format, a resize, … should be. "Add to plan" only adds the step
// to the plan (Disks.qml); nothing is written before the plan is applied.
// Which fields show depends on `action`.
ColumnLayout {
    id: root

    required property string action
    property var segment: null // the partition or free space it's for
    property var drive: null // as the plan leaves it

    readonly property int mib: 1048576
    readonly property bool hasSize: ["create", "resize"].includes(action)
    readonly property bool hasFilesystem: ["create", "format", "erase"].includes(action)
    readonly property bool hasTable: ["table", "erase"].includes(action)
    readonly property bool hasName: (action === "create" && drive?.table === "gpt") || action === "name"
    readonly property bool asksPassphrase: ["unlock", "passphrase"].includes(action)
    readonly property bool choosesPassphrase: action === "passphrase" || (hasFilesystem && encrypt.checked)
    readonly property bool showsLabel: action === "label" || (hasFilesystem && (chosenFilesystem?.labelLimit ?? 0) > 0)

    readonly property real maxSize: {
        if (action === "resize") {
            return segment?.maxSize ?? 0;
        }
        return segment?.size ?? 0;
    }
    // A size typed a little over the maximum is the maximum, rounded
    readonly property real size: {
        const typed = Disks.parseSize(sizeField.text);
        if (typed > maxSize && typed <= maxSize * 1.005) {
            return maxSize;
        }
        return typed;
    }
    readonly property var available: Disks.filesystems.filter(f => f.available)
    readonly property var missing: Disks.filesystems.filter(f => !f.available)
    property string fs: "ext4"
    property string table: "gpt"
    property string partitionType: segment?.type ?? ""
    readonly property var chosenFilesystem: Disks.filesystems.find(f => f.id === fs) ?? null

    readonly property string problem: {
        if (hasSize && (size <= 0 || size > maxSize)) {
            return I18n.tr("A size up to %1, like 8 GB or 500 MB", Disks.sizeText(maxSize));
        }
        if (asksPassphrase && passphrase.text === "") {
            return I18n.tr("Enter the passphrase");
        }
        if (choosesPassphrase && newPassphrase.text === "") {
            return I18n.tr("Enter a new passphrase");
        }
        if (choosesPassphrase && newPassphrase.text !== repeat.text) {
            return I18n.tr("The passphrases differ");
        }
        return "";
    }

    readonly property var titles: ({
            create: I18n.tr("New partition"),
            format: I18n.tr("Format"),
            erase: I18n.tr("Erase the whole drive"),
            resize: I18n.tr("Resize"),
            label: I18n.tr("Label"),
            name: I18n.tr("Partition name"),
            type: I18n.tr("Partition type"),
            table: I18n.tr("New partition table"),
            unlock: I18n.tr("Unlock"),
            passphrase: I18n.tr("Change the passphrase")
        })

    Component.onCompleted: {
        sizeField.text = Disks.sizeText(maxSize);
        labelField.text = action === "label" ? segment?.label ?? "" : "";
        nameField.text = action === "name" ? segment?.name ?? "" : "";
        if (!available.some(f => f.id === fs)) {
            fs = available[0]?.id ?? "";
        }
    }

    function newVolume() {
        return {
            fs: fs,
            label: labelField.text,
            passphrase: encrypt.checked ? newPassphrase.text : "",
            erase: erase.checked
        };
    }

    function steps() {
        const target = segment?.id ?? "";
        switch (action) {
        case "create":
            return [Object.assign({
                    op: "create",
                    offset: segment.offset,
                    size: size,
                    name: nameField.text
                }, newVolume())];
        case "erase":
            // One partition over all of it, inside the new table's free space
            return [
                {
                    op: "table",
                    type: table
                },
                Object.assign({
                    op: "create",
                    offset: mib,
                    size: drive.size - 2 * mib
                }, newVolume())];
        case "format":
            return [Object.assign({
                    op: "format",
                    target: target
                }, newVolume())];
        case "resize":
            return [
                {
                    op: "resize",
                    target: target,
                    size: size
                }
            ];
        case "label":
        case "name":
            return [
                {
                    op: action,
                    target: target,
                    value: action === "label" ? labelField.text : nameField.text
                }
            ];
        case "type":
            return [
                {
                    op: "type",
                    target: target,
                    value: partitionType
                }
            ];
        case "table":
            return [
                {
                    op: "table",
                    type: table
                }
            ];
        case "unlock":
            return [
                {
                    op: "unlock",
                    target: target,
                    passphrase: passphrase.text
                }
            ];
        case "passphrase":
            return [
                {
                    op: "passphrase",
                    target: target,
                    passphrase: passphrase.text,
                    value: newPassphrase.text
                }
            ];
        }
        return [];
    }

    function submit() {
        if (problem === "") {
            Disks.add(steps());
        }
    }

    spacing: 8

    SectionTitle {
        text: root.titles[root.action] ?? root.action
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 6

        Label {
            visible: root.hasTable
            text: I18n.tr("Partition table")
            color: Theme.subtext0
        }
        Dropdown {
            Layout.fillWidth: true
            visible: root.hasTable
            model: {
                const tables = [
                    {
                        text: I18n.tr("GPT, for current systems"),
                        value: "gpt"
                    },
                    {
                        text: I18n.tr("MBR, for old devices"),
                        value: "dos"
                    }
                ];
                if (root.action === "table") {
                    tables.push({
                        text: I18n.tr("None, wipe it"),
                        value: "empty"
                    });
                }
                return tables;
            }
            current: root.table
            onPicked: value => root.table = value
        }

        Label {
            visible: root.hasSize
            text: I18n.tr("Size")
            color: Theme.subtext0
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasSize
            spacing: 6

            InputField {
                id: sizeField
                Layout.fillWidth: true
                placeholder: "8 GB"
                onAccepted: root.submit()
            }
            IconButton {
                text: I18n.tr("All of it")
                onClicked: sizeField.text = Disks.sizeText(root.maxSize)
            }
        }

        Label {
            visible: root.hasFilesystem
            text: I18n.tr("Filesystem")
            color: Theme.subtext0
        }
        Dropdown {
            Layout.fillWidth: true
            visible: root.hasFilesystem
            model: root.available.map(f => ({
                        text: `${f.title} · ${f.detail}`,
                        value: f.id
                    }))
            current: root.fs
            onPicked: value => root.fs = value
        }
        Item {
            visible: root.hasFilesystem && root.missing.length > 0
        }
        Label {
            Layout.fillWidth: true
            visible: root.hasFilesystem && root.missing.length > 0
            text: I18n.tr("Not installed: %1", root.missing.map(f => f.title).join(", "))
            color: Theme.overlay1
            font.pixelSize: 11
        }

        Label {
            visible: root.showsLabel
            text: I18n.tr("Label")
            color: Theme.subtext0
        }
        InputField {
            id: labelField
            Layout.fillWidth: true
            visible: root.showsLabel
            placeholder: I18n.tr("Shown as the drive's name")
            onAccepted: root.submit()
        }

        Label {
            visible: root.hasName
            text: I18n.tr("Partition name")
            color: Theme.subtext0
        }
        InputField {
            id: nameField
            Layout.fillWidth: true
            visible: root.hasName
            onAccepted: root.submit()
        }

        Label {
            visible: root.action === "type"
            text: I18n.tr("Type")
            color: Theme.subtext0
        }
        Dropdown {
            Layout.fillWidth: true
            visible: root.action === "type"
            model: (Disks.types[root.drive?.table] ?? []).map(t => ({
                        text: t.title,
                        value: t.id
                    }))
            current: root.partitionType
            onPicked: value => root.partitionType = value
        }

        Label {
            visible: root.hasFilesystem && (root.chosenFilesystem?.encryptable ?? false)
            text: I18n.tr("Encrypt (LUKS)")
            color: Theme.subtext0
        }
        Switch {
            id: encrypt
            visible: root.hasFilesystem && (root.chosenFilesystem?.encryptable ?? false)
            onToggled: checked = !checked
        }

        Label {
            visible: root.asksPassphrase
            text: root.action === "passphrase" ? I18n.tr("Current passphrase") : I18n.tr("Passphrase")
            color: Theme.subtext0
        }
        InputField {
            id: passphrase
            Layout.fillWidth: true
            visible: root.asksPassphrase
            masked: true
            onAccepted: root.submit()
        }
        Label {
            visible: root.choosesPassphrase
            text: root.action === "passphrase" ? I18n.tr("New passphrase") : I18n.tr("Passphrase")
            color: Theme.subtext0
        }
        InputField {
            id: newPassphrase
            Layout.fillWidth: true
            visible: root.choosesPassphrase
            masked: true
        }
        Label {
            visible: root.choosesPassphrase
            text: I18n.tr("Repeat it")
            color: Theme.subtext0
        }
        InputField {
            id: repeat
            Layout.fillWidth: true
            visible: root.choosesPassphrase
            masked: true
            onAccepted: root.submit()
        }

        Label {
            visible: root.hasFilesystem
            text: I18n.tr("Overwrite with zeros")
            color: Theme.subtext0
        }
        RowLayout {
            visible: root.hasFilesystem
            spacing: 8

            Switch {
                id: erase
                onToggled: checked = !checked
            }
            Label {
                text: I18n.tr("Slow; the old data can't be recovered then")
                color: Theme.overlay1
                font.pixelSize: 11
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.problem !== ""
        text: root.problem
        color: Theme.peach
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Item {
            Layout.fillWidth: true
        }
        IconButton {
            text: I18n.tr("Cancel")
            onClicked: Disks.form = ""
        }
        IconButton {
            glyph: Theme.glyph(0xf0415) // 󰐕
            text: I18n.tr("Add to plan")
            active: root.problem === ""
            opacity: root.problem === "" ? 1 : 0.5
            onClicked: root.submit()
        }
    }
}
