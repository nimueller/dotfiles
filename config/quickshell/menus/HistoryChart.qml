import QtQuick

// Line chart over time for the battery history (battery-history.qml): one
// value per sample, broken where samples are missing (suspended, off), in
// `color` and in `chargeColor` while charging, filled below. With
// `connectGaps` gaps up to `shortGap` are drawn as if there were samples,
// and a dashed line bridges each longer one, from the last value before it
// to the first after it. `estimates` are averages over times without
// samples, drawn as a dashed level. Hover for the value at that time.
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
    property bool connectGaps: false
    property real shortGap: 900 // s, with connectGaps
    property var estimates: [] // [{ from, to (s), v }]

    readonly property real plotLeft: 34
    readonly property real plotBottom: height - 18
    property int hovered: -1
    property int hoveredEstimate: -1
    property real hoverTime: 0

    function xOf(t) {
        return plotLeft + (t - from) / (to - from) * (width - plotLeft);
    }
    function yOf(v) {
        return plotBottom - Math.min(1, Math.max(0, v / maxValue)) * (plotBottom - 4);
    }

    // The samples split up: runs of connected samples with the same state,
    // thinned to about one per pixel, and the breaks between runs where
    // samples are missing, as [last before, first after]
    function segments() {
        const pixel = (to - from) / Math.max(1, width - plotLeft);
        // A logger restart or a short suspend says nothing about the charge
        const longestJoined = connectGaps ? Math.max(gap, shortGap) : gap;
        const runs = [];
        const breaks = [];
        let run = [];
        let seen = null; // the last sample, drawn or not
        for (const p of samples) {
            if (p.t < from - gap) {
                seen = p;
                continue;
            }
            const isBroken = seen !== null && p.t - seen.t > longestJoined;
            const isNewState = seen !== null && p.charging !== seen.charging;
            if (isBroken) {
                breaks.push([seen, p]);
            }
            if (isBroken || isNewState) {
                runs.push(finished(run, seen));
                run = isBroken ? [] : [carriedOver(seen, p)];
            } else if (run.length > 0 && p.t - run[run.length - 1].t < pixel) {
                seen = p;
                continue;
            }
            run.push(p);
            seen = p;
        }
        runs.push(finished(run, seen));
        return {
            runs: runs.filter(r => r.length > 1),
            breaks: breaks
        };
    }

    // A run ends on its last sample, also when the thinning left it out
    function finished(run, last) {
        if (run.length > 0 && run[run.length - 1] !== last) {
            run.push(last);
        }
        return run;
    }

    // A new state carries on from the last point
    function carriedOver(last, next) {
        return Object.assign({}, last, {
            charging: next.charging
        });
    }

    // Quarters of the scale
    function drawGrid(ctx) {
        ctx.strokeStyle = Theme.surface0;
        ctx.lineWidth = 1;
        for (let i = 0; i <= 4; i++) {
            const y = Math.round(yOf(maxValue * i / 4)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(plotLeft, y);
            ctx.lineTo(width, y);
            ctx.stroke();
        }
    }

    function drawRun(ctx, run) {
        const c = run[0].charging ? chargeColor : color;
        const last = run[run.length - 1];
        ctx.beginPath();
        ctx.moveTo(xOf(run[0].t), plotBottom);
        for (const p of run) {
            ctx.lineTo(xOf(p.t), yOf(p.v));
        }
        ctx.lineTo(xOf(last.t), plotBottom);
        ctx.closePath();
        ctx.fillStyle = Theme.alpha(c, 0.15);
        ctx.fill();
        ctx.beginPath();
        ctx.moveTo(xOf(run[0].t), yOf(run[0].v));
        for (const p of run.slice(1)) {
            ctx.lineTo(xOf(p.t), yOf(p.v));
        }
        ctx.strokeStyle = c;
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }

    // Dashed and barely filled: an average over that time, not samples
    function drawEstimates(ctx) {
        ctx.save();
        ctx.setLineDash([3, 3]);
        ctx.strokeStyle = color;
        ctx.lineWidth = 1;
        ctx.fillStyle = Theme.alpha(color, 0.06);
        for (const estimate of estimates) {
            const left = xOf(estimate.from);
            const right = xOf(estimate.to);
            const y = yOf(estimate.v);
            ctx.fillRect(left, y, right - left, plotBottom - y);
            ctx.beginPath();
            ctx.moveTo(left, y);
            ctx.lineTo(right, y);
            ctx.stroke();
        }
        ctx.restore();
    }

    function timeAt(x) {
        return from + (x - plotLeft) / (width - plotLeft) * (to - from);
    }

    // The index of the sample nearest to t, -1 when none is within gap
    function nearestSample(t) {
        const s = samples;
        if (s.length === 0) {
            return -1;
        }
        let lo = 0;
        let hi = s.length - 1;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (s[mid].t < t) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        if (lo > 0 && Math.abs(s[lo - 1].t - t) < Math.abs(s[lo].t - t)) {
            lo--;
        }
        return Math.abs(s[lo].t - t) <= gap ? lo : -1;
    }

    function estimateAt(t) {
        return estimates.findIndex(e => e.from <= t && t <= e.to);
    }

    function valueText(v) {
        const unitText = unit === "%" ? "%" : ` ${unit}`;
        return `${v.toFixed(decimals)}${unitText}`;
    }

    function sampleText(sample) {
        const time = Qt.formatDateTime(new Date(sample.t * 1000), "ddd HH:mm");
        const charging = sample.charging ? " · charging" : "";
        return `${time} · ${valueText(sample.v)}${charging}`;
    }

    function estimateText(estimate) {
        const start = Qt.formatDateTime(new Date(estimate.from * 1000), "ddd HH:mm");
        const end = Qt.formatTime(new Date(estimate.to * 1000), "HH:mm");
        return `${start} – ${end} · ≈ ${valueText(estimate.v)} average`;
    }

    // Dashed: what happened in between wasn't recorded
    function drawBreaks(ctx, breaks) {
        ctx.save();
        ctx.setLineDash([3, 3]);
        ctx.strokeStyle = Theme.overlay1;
        ctx.lineWidth = 1;
        for (const [before, after] of breaks) {
            ctx.beginPath();
            ctx.moveTo(xOf(before.t), yOf(before.v));
            ctx.lineTo(xOf(after.t), yOf(after.v));
            ctx.stroke();
        }
        ctx.restore();
    }

    // Labels along the time axis: every few hours for a day, else days
    // A tick's label: the time within a day, else the weekday or the date
    function tickLabel(date, step) {
        if (step < 86400) {
            return Qt.formatTime(date, "HH:mm");
        }
        if (step === 86400) {
            return Qt.formatDate(date, "ddd");
        }
        return Qt.formatDate(date, "d.M.");
    }

    readonly property var ticks: {
        const span = to - from, out = [];
        let step = 5 * 86400;
        if (span <= 2 * 86400) {
            step = 6 * 3600;
        } else if (span <= 10 * 86400) {
            step = 86400;
        }
        const start = new Date(from * 1000);
        if (step < 86400) {
            start.setMinutes(0, 0, 0), start.setHours(Math.ceil(start.getHours() / 6) * 6);
        } else {
            start.setHours(24, 0, 0, 0);
        }
        for (let d = start; d.getTime() / 1000 < to; d = new Date(d.getTime() + step * 1000)) {
            out.push({
                t: d.getTime() / 1000,
                text: tickLabel(d, step)
            });
        }
        return out;
    }

    onSamplesChanged: canvas.requestPaint()
    onFromChanged: canvas.requestPaint()
    onToChanged: canvas.requestPaint()
    onMaxValueChanged: canvas.requestPaint()
    onEstimatesChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            root.drawGrid(ctx);
            // Breaks can start before the range: keep them off the scale
            ctx.beginPath();
            ctx.rect(root.plotLeft, 0, width - root.plotLeft, height);
            ctx.clip();
            const parts = root.segments();
            for (const run of parts.runs) {
                root.drawRun(ctx, run);
            }
            if (root.connectGaps) {
                root.drawBreaks(ctx, parts.breaks);
            }
            root.drawEstimates(ctx);
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

    // Hover: the nearest sample, else the estimate there
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onExited: {
            root.hovered = -1;
            root.hoveredEstimate = -1;
        }
        onPositionChanged: event => {
            const t = root.timeAt(event.x);
            const isInPlot = event.x >= root.plotLeft;
            root.hoverTime = t;
            root.hovered = isInPlot ? root.nearestSample(t) : -1;
            root.hoveredEstimate = isInPlot && root.hovered < 0 ? root.estimateAt(t) : -1;
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
        readonly property var estimate: root.hoveredEstimate >= 0 ? root.estimates[root.hoveredEstimate] : null
        readonly property real anchorTime: sample ? sample.t : root.hoverTime

        visible: !!sample || !!estimate
        x: Math.min(root.width - width, Math.max(root.plotLeft, root.xOf(anchorTime) + 8))
        y: 4
        width: tipLabel.implicitWidth + 12
        height: tipLabel.implicitHeight + 6
        radius: 6
        color: Theme.surface0

        Label {
            id: tipLabel
            anchors.centerIn: parent
            text: {
                if (tip.sample) {
                    return root.sampleText(tip.sample);
                }
                if (tip.estimate) {
                    return root.estimateText(tip.estimate);
                }
                return "";
            }
            font.pixelSize: 10
        }
    }
}
