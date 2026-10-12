import QtQuick
import Quickshell.Services.Pipewire

// Volume of a PipeWire node on a Slider, dimmed while muted
Slider {
    required property PwNode node

    value: Math.min(node?.audio?.volume ?? 0, 1)
    dimmed: node?.audio?.muted ?? false
    onMoved: v => Audio.setVolume(node, v)
}
