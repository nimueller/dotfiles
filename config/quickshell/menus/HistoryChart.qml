import QtQuick

// Line chart over time for the battery history (battery-history.qml): one
// value per sample, broken where samples are missing (suspended, off), in
// `color` and in `chargeColor` while charging, filled below. Hover for the
// value at that time.
Item {
    id: root

    property var samples: [] // [{ t (s), v, charging }], oldest first
    property real from: 0 // s
    property real to: 1
    property real maxValue: 100
    property string unit: "%"
    property int decimals: 0
    property color color: Theme.blue
    property color chargeColor: Theme.teal
    property real gap: 180 // s between samples that still connect

    readonly property real plotLeft: 34
    readonly property real plotBottom: height - 18
    property int hovered: -1

    function xOf(t) {
        return plotLeft + (t - from) / (to - from) * (width - plotLeft);
    }
    function yOf(v) {
        return plotBottom - Math.min(1, Math.max(0, v / maxValue)) * (plotBottom - 4);
    }

    // Labels along the time axis: every few hours for a day, else days
    readonly property var ticks: {
        const span = to - from, out = [];
        const step = span <= 2 * 86400 ? 6 * 3600 : span <= 10 * 86400 ? 86400 : 5 * 86400;
        const start = new Date(from * 1000);
        if (step < 86400)
            start.setMinutes(0, 0, 0), start.setHours(Math.ceil(start.getHours() / 6) * 6);
        else
            start.setHours(24, 0, 0, 0);
        for (let d = start; d.getTime() / 1000 < to; d = new Date(d.getTime() + step * 1000))
            out.push({ t: d.getTime() / 1000, text: step < 86400 ? Qt.formatTime(d, "HH:mm") : step === 86400 ? Qt.formatDate(d, "ddd") : Qt.formatDate(d, "d.M.") });
        return out;
    }

    onSamplesChanged: canvas.requestPaint()
    onFromChanged: canvas.requestPaint()
    onToChanged: canvas.requestPaint()
    onMaxValueChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            // Grid: quarters of the scale
            ctx.strokeStyle = Theme.surface0;
            ctx.lineWidth = 1;
            for (let i = 0; i <= 4; i++) {
                const y = Math.round(root.yOf(root.maxValue * i / 4)) + 0.5;
                ctx.beginPath();
                ctx.moveTo(root.plotLeft, y);
                ctx.lineTo(width, y);
                ctx.stroke();
            }

            // Runs of connected samples with the same state, thinned to
            // about one per pixel
            const s = root.samples;
            const pixel = (root.to - root.from) / Math.max(1, width - root.plotLeft);
            let run = [];
            const flush = () => {
                if (run.length > 1) {
                    const c = run[0].charging ? root.chargeColor : root.color;
                    ctx.beginPath();
                    ctx.moveTo(root.xOf(run[0].t), root.plotBottom);
                    for (const p of run)
                        ctx.lineTo(root.xOf(p.t), root.yOf(p.v));
                    ctx.lineTo(root.xOf(run[run.length - 1].t), root.plotBottom);
                    ctx.closePath();
                    ctx.fillStyle = Theme.alpha(c, 0.15);
                    ctx.fill();
                    ctx.beginPath();
                    run.forEach((p, i) => i ? ctx.lineTo(root.xOf(p.t), root.yOf(p.v)) : ctx.moveTo(root.xOf(p.t), root.yOf(p.v)));
                    ctx.strokeStyle = c;
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
            };
            let seen = null; // the last sample, drawn or not
            const end = () => {
                if (seen && run[run.length - 1] !== seen)
                    run.push(seen);
            };
            for (const p of s) {
                if (p.t < root.from - root.gap)
                    continue;
                if (seen && (p.t - seen.t > root.gap || p.charging !== seen.charging)) {
                    end();
                    flush();
                    // A new state carries on from the last point
                    run = p.t - seen.t <= root.gap ? [Object.assign({}, seen, { charging: p.charging })] : [];
                } else if (run.length && p.t - run[run.length - 1].t < pixel) {
                    seen = p;
                    continue;
                }
                run.push(p);
                seen = p;
            }
            end();
            flush();
        }
    }

    // Scale and time labels
    Repeater {
        model: [0, 0.5, 1]

        delegate: Label {
            required property real modelData
            x: 0
            width: root.plotLeft - 6
            y: root.yOf(root.maxValue * modelData) - height / 2
            horizontalAlignment: Text.AlignRight
            text: `${+(root.maxValue * modelData).toFixed(root.maxValue < 10 ? 1 : 0)}${root.unit === "%" ? "%" : ""}`
            font.pixelSize: 9
            color: Theme.overlay0
        }
    }
    Repeater {
        model: root.ticks

        delegate: Label {
            required property var modelData
            x: root.xOf(modelData.t) - width / 2
            y: root.plotBottom + 4
            text: modelData.text
            font.pixelSize: 9
            color: Theme.overlay0
        }
    }

    // Hover: the nearest sample
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onExited: root.hovered = -1
        onPositionChanged: event => {
            const t = root.from + (event.x - root.plotLeft) / (root.width - root.plotLeft) * (root.to - root.from);
            const s = root.samples;
            let lo = 0, hi = s.length - 1;
            while (lo < hi) {
                const mid = (lo + hi) >> 1;
                if (s[mid].t < t)
                    lo = mid + 1;
                else
                    hi = mid;
            }
            if (lo > 0 && Math.abs(s[lo - 1].t - t) < Math.abs(s[lo].t - t))
                lo--;
            root.hovered = s.length && event.x >= root.plotLeft && Math.abs(s[lo].t - t) <= root.gap ? lo : -1;
        }
    }

    Rectangle {
        visible: root.hovered >= 0
        x: visible ? Math.round(root.xOf(root.samples[root.hovered].t)) : 0
        y: 4
        width: 1
        height: root.plotBottom - 4
        color: Theme.overlay0
    }
    Rectangle {
        id: tip

        readonly property var sample: root.hovered >= 0 ? root.samples[root.hovered] : null

        visible: !!sample
        x: sample ? Math.min(root.width - width, Math.max(root.plotLeft, root.xOf(sample.t) + 8)) : 0
        y: 4
        width: tipLabel.implicitWidth + 12
        height: tipLabel.implicitHeight + 6
        radius: 6
        color: Theme.surface0

        Label {
            id: tipLabel
            anchors.centerIn: parent
            text: tip.sample ? `${Qt.formatDateTime(new Date(tip.sample.t * 1000), "ddd HH:mm")} · ${tip.sample.v.toFixed(root.decimals)}${root.unit === "%" ? "%" : ` ${root.unit}`}${tip.sample.charging ? " · charging" : ""}` : ""
            font.pixelSize: 10
        }
    }
}
