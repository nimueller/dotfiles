import QtQuick

// A drive's partitions and free space side by side, each as wide as its share
// of the drive, but at least a sliver, so a small one can still be clicked
// (disks.qml). Free space is an outline; a partition the plan changes has a
// peach outline, the picked one a light one. picked(id) reports a click.
Item {
    id: root

    property var drive: null
    property string selected: ""
    readonly property var segments: drive?.segments ?? []
    readonly property int gap: 2
    readonly property int sliver: 12
    readonly property var widths: layOut(width)

    signal picked(string id)

    implicitHeight: Modes.touch ? 44 : 34

    // The slivers first, the rest of the width shared by size among the others
    function layOut(total) {
        const room = total - gap * Math.max(0, segments.length - 1);
        const driveSize = segments.reduce((sum, s) => sum + s.size, 0) || 1;
        const small = segments.map(s => s.size / driveSize * room < sliver);
        const smallCount = small.filter(isSmall => isSmall).length;
        const bigSize = segments.reduce((sum, s, i) => small[i] ? sum : sum + s.size, 0) || 1;
        const bigRoom = room - smallCount * sliver;
        return segments.map((s, i) => small[i] ? sliver : s.size / bigSize * bigRoom);
    }

    function outline(segment) {
        if (segment.id === selected) {
            return Theme.text;
        }
        if (segment.changed) {
            return Theme.peach;
        }
        return segment.kind === "free" ? Theme.surface2 : "transparent";
    }

    Row {
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: root.segments

            delegate: Rectangle {
                id: block

                required property var modelData
                required property int index
                readonly property bool isFree: modelData.kind === "free"

                width: root.widths[index] ?? 0
                height: root.height
                radius: 6
                color: isFree ? "transparent" : Theme.alpha(Disks.color(modelData), mouse.containsMouse ? 0.85 : 0.65)
                border.width: modelData.id === root.selected || modelData.changed ? 2 : 1
                border.color: root.outline(modelData)

                Label {
                    anchors.fill: parent
                    anchors.margins: 4
                    horizontalAlignment: Text.AlignHCenter
                    visible: block.width > 48
                    text: block.isFree ? block.modelData.sizeText : block.modelData.title
                    font.pixelSize: 10
                    color: block.isFree ? Theme.overlay1 : Theme.readableOn(Disks.color(block.modelData))
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(block.modelData.id)
                }
            }
        }
    }
}
