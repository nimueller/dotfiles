// Text in the bar, in the bar's own font; bigger in touch mode
Label {
    font.family: Theme.barFont
    font.pixelSize: Modes.touch ? 15 : 12
}
