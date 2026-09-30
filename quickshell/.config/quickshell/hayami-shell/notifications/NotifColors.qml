import QtQuick

// Resolves the notification theme's colour names onto the pywal palette.
//
// The theme's notifications.css and central_control.css each started with
// a block of @define-color lines naming pywal colours, and the two disagreed on two of
// them (the popups hover with @color5 and paint actions with @color1; the control
// centre hovers with a half-transparent @color1 and paints actions with
// @color1 at 60%). Rather than repeat that mapping in every component, the
// popup and the panel each instantiate one of these and read the names from
// here -- so a wallpaper change re-tints the whole notification stack.
QtObject {
    id: root

    // The BarPalette instance to read from.
    required property var pal

    readonly property var list: (pal && pal.colors && pal.colors.length >= 16) ? pal.colors : null

    function pywal(index) {
        return list ? list[index] : root.text
    }

    // .control-center, .notification-background { background: alpha(@background, .95) }
    readonly property color background: pal ? pal.background : "#171513"
    readonly property color text: pal ? pal.foreground : "#c5c4c4"

    readonly property color cardBackground: Qt.rgba(background.r, background.g, background.b, 0.95)

    // border-alt: @color6
    readonly property color border: pywal(6)
    // notifications.css: selected: @color1 / hover: @color5 / urgent: @color2
    readonly property color selected: pywal(1)
    readonly property color hover: pywal(5)
    readonly property color urgent: pywal(2)

    // central_control.css redefines these.
    // background-alt: alpha(@color6, .25)
    readonly property color backgroundAlt: Qt.rgba(border.r, border.g, border.b, 0.25)
    // hover: alpha(@selected, .5)
    readonly property color hoverAlt: Qt.rgba(selected.r, selected.g, selected.b, 0.5)
    // .notification-action { background: alpha(@selected, .6) }
    readonly property color actionBackground: Qt.rgba(selected.r, selected.g, selected.b, 0.6)

    // .widget-volume scale trough { background-color: alpha(@text, .15) }
    readonly property color track: Qt.rgba(text.r, text.g, text.b, 0.15)
    // .widget-volume > box > button { color: alpha(@text, .5) }
    readonly property color dimText: Qt.rgba(text.r, text.g, text.b, 0.5)

    // progressbar { background-color: rgba(255,255,255,.1) }
    readonly property color progressTrack: Qt.rgba(1, 1, 1, 0.1)
    readonly property color progress: selected
}
