import QtQuick
import "NotifTheme.js" as Theme

// One row of the panel's volume/brightness section: a glyph, a trough with a
// fill, and a round handle on top of it.
//
// central_control.css, .widget-volume:
//   scale { min-height: 16px }
//   scale trough { background-color: alpha(@text,.15); border-radius: 8px;
//                  min-height: 8px }
//   scale trough highlight { background-color: @selected; border-radius: 8px }
//   scale slider { background-color: @text; border-radius: 50%; min-width: 16px;
//                  min-height: 16px; margin: -4px }
//   .widget-volume > box > label { margin-right: 10px }
//
// It maps a pointer position onto 0..100 and reports it; what that number means
// -- a sink's volume, a backlight's percentage -- is the owner's business. Both
// sliders of the section are one of these, which is why the brightness row added
// to the panel looks and behaves like the volume row swaync drew.
Item {
	id: root

	required property var notifColors

	// The nerd-font glyph at the left, as the volume row has always had.
	property string glyph: ""
	// 0..100, the range swaync's scales use.
	property real value: 0
	// Muted: the fill goes grey instead of taking the accent colour.
	property bool dim: false
	// The panel's keyboard is on this knob. The cursor is a ring around the
	// knob rather than a highlight over the row, because the knob is the thing
	// the horizontal keys move.
	property bool focused: false
	// The glyph is this row's mute button. Only the volume row has anything to
	// mute, so the brightness one leaves it as plain text.
	property bool glyphClickable: false
	// The glyph's advance width, fixed by the owner across every glyph it can
	// show in that slot. Without it the trough beside the glyph slides sideways
	// whenever the glyph changes: the mute icon is about 9px narrower than the
	// volume one, which pulled the scale left -- and its click target with it,
	// so a click on the icon landed on the slider instead. It also lines the
	// volume and brightness troughs up on the same x.
	property real glyphWidth: 0

	signal moved(real value)
	signal glyphClicked()

	implicitHeight: Theme.sliderSize

	Text {
		id: glyphLabel

		anchors.left: parent.left
		anchors.leftMargin: Theme.volumePadding
		anchors.verticalCenter: parent.verticalCenter
		width: root.glyphWidth > 0 ? root.glyphWidth : implicitWidth
		text: root.glyph
		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize + 4
		color: (root.glyphClickable && glyphArea.containsMouse) ? root.notifColors.selected : root.notifColors.text
	}

	// The target is the whole tag left of the trough: the glyph's box, its
	// padding, and the gap out to where the slider starts. It has to be the whole
	// tag because the glyph's ink is wider than its advance width -- a nerd-font
	// codepoint the installed font draws from a fallback face ~20px wide inside a
	// ~10px box -- so an area fitted to the box would leave the icon's right half
	// unclickable. It is the same "hover tints, click acts" the media buttons use,
	// so it needs no icon of its own to read as clickable.
	MouseArea {
		id: glyphArea

		anchors.left: glyphLabel.left
		anchors.leftMargin: -Theme.volumePadding
		anchors.right: scale.left
		anchors.top: glyphLabel.top
		anchors.topMargin: -Theme.volumePadding
		anchors.bottom: glyphLabel.bottom
		anchors.bottomMargin: -Theme.volumePadding
		enabled: root.glyphClickable
		hoverEnabled: root.glyphClickable
		cursorShape: root.glyphClickable ? Qt.PointingHandCursor : Qt.ArrowCursor
		onClicked: root.glyphClicked()
	}

	Item {
		id: scale

		anchors.left: glyphLabel.right
		anchors.leftMargin: Theme.volumeLabelGap
		anchors.right: parent.right
		anchors.rightMargin: Theme.volumePadding
		anchors.verticalCenter: parent.verticalCenter
		height: Theme.sliderSize

		// The handle is this wide, so the trough has this much less to travel.
		readonly property real usable: Math.max(0, width - Theme.sliderSize)
		readonly property real shown: Math.max(0, Math.min(100, root.value))
		readonly property real knobX: usable * (shown / 100)

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			width: parent.width
			height: Theme.troughHeight
			radius: Theme.troughHeight / 2
			color: root.notifColors.track
		}

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			anchors.left: parent.left
			width: parent.knobX + Theme.sliderSize / 2
			height: Theme.troughHeight
			radius: Theme.troughHeight / 2
			color: root.dim ? root.notifColors.dimText : root.notifColors.progress
		}

		Rectangle {
			id: knob

			x: parent.knobX
			width: Theme.sliderSize
			height: Theme.sliderSize
			radius: Theme.sliderSize / 2
			color: root.notifColors.text
		}

		// The ring is drawn outside the knob rather than as a border on it: half
		// the knob's radius is border, which would eat the handle at 16px. At an
		// end of the scale it overhangs the trough, which is also how it reads as
		// “the end” rather than as a stuck knob.
		Rectangle {
			x: knob.x - Theme.sliderRingGap
			y: knob.y - Theme.sliderRingGap
			width: knob.width + Theme.sliderRingGap * 2
			height: knob.height + Theme.sliderRingGap * 2
			radius: width / 2
			// Hovered as well as focused: the knob is what a click grabs, so
			// pointing at the row should say so before the keyboard arrives on it.
			visible: root.focused || hover.hovered
			color: "transparent"
			border.width: Theme.sliderRingBorder
			border.color: root.notifColors.selected
		}

		// Hover is read with a handler of its own rather than by turning hover on
		// for the MouseArea below: that would also make its positionChanged fire
		// while the pointer merely moves, which would scrub the level on a hover.
		HoverHandler {
			id: hover
		}

		// The overhang is vertical only. Reaching past the trough's ends would buy
		// nothing -- the knob is drawn inside the trough, and a press keeps the
		// grab while it drags -- and on the left it reached over the mute tag,
		// where a click aimed at the icon's right half landed on the slider and
		// set the volume to 0 instead.
		MouseArea {
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.top: parent.top
			anchors.bottom: parent.bottom
			anchors.topMargin: -Theme.sliderSize / 2
			anchors.bottomMargin: -Theme.sliderSize / 2
			cursorShape: Qt.PointingHandCursor
			onPressed: (mouse) => scale.report(mouse.x - Theme.sliderSize / 2)
			onPositionChanged: (mouse) => scale.report(mouse.x - Theme.sliderSize / 2)
		}

		// A position inside the scale as 0..100. Dragging past either end clamps
		// rather than overshooting into the volume-boost range, which is what
		// swaync's 0..100 scale does.
		function report(x) {
			var fraction = scale.usable > 0 ? x / scale.usable : 0;
			root.moved(Math.max(0, Math.min(1, fraction)) * 100);
		}
	}
}
