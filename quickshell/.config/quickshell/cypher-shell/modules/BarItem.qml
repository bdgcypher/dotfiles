import QtQuick
import "Theme.js" as Theme

// Shared building block for every bar module.
//
// Mirrors waybar's module model so the spacing rules in style.css carry over:
// a fixed-height text cell whose width is its glyph plus explicit left/right
// margins (waybar's `margin: 0 7.5px` and friends), with an optional min-width
// so the bar does not shift when a value gains or loses a digit.
Item {
	id: root

	property var pal: null
	property string glyph: ""
	property string suffix: ""
	property string fontFamily: Theme.fontFamily
	property real fontSize: Theme.fontSize
	property color tint: pal ? pal.foreground : "#c5c4c4"
	property real dim: 1.0
	property bool pulse: false
	property real minWidth: 0
	// A small filled badge on the glyph's top-right corner, for a module whose
	// state is otherwise not worth recolouring the whole icon for (the bell).
	property bool dot: false
	property color dotColor: pal ? pal.alert : "#a55555"
	property real dotSize: 9
	property real marginLeft: 0
	property real marginRight: 0
	property real paddingLeft: 0
	property real paddingRight: 0

	// The tooltip shown while the pointer rests on this module, or "" for none
	// -- waybar's `"tooltip": false`, and what the clock and the tray chevron
	// are configured with. Every module that has one sets it, so there is no
	// separate switch to keep in step with the text.
	property string tooltipText: ""

	signal clicked()
	signal rightClicked()
	signal scrolled(int delta)

	// waybar renders no module whose text is empty: it takes no width, no padding
	// and no margin. That is what keeps the centre section centred while the
	// update / dictation / recording indicators have nothing to say, so the cell
	// collapses to nothing here too (minWidth only applies once there is a glyph).
	readonly property bool empty: (glyph + suffix).length === 0

	implicitWidth: empty ? 0 : Math.max(label.implicitWidth, minWidth) + marginLeft + marginRight + paddingLeft + paddingRight
	implicitHeight: Theme.height
	visible: !empty

	// Drives the recording/dictation pulse. waybar animates the colour from
	// transparent to #a55555 and back over 1.5s; fading this cell's opacity at
	// the same rate over the same period reads identically.
	property real pulseMix: 1.0

	SequentialAnimation {
		running: root.pulse
		loops: Animation.Infinite
		NumberAnimation {
			target: root
			property: "pulseMix"
			from: 0.0
			to: 1.0
			duration: Theme.pulseDuration
		}
		NumberAnimation {
			target: root
			property: "pulseMix"
			from: 1.0
			to: 0.0
			duration: Theme.pulseDuration
		}
	}

	Text {
		id: label

		anchors.centerIn: parent
		anchors.horizontalCenterOffset: (root.marginLeft + root.paddingLeft - root.marginRight - root.paddingRight) / 2
		text: root.glyph + root.suffix
		color: root.pulse ? Theme.pulseColor : root.tint
		opacity: root.pulse ? root.pulseMix : root.dim
		font.family: root.fontFamily
		font.pixelSize: root.fontSize
		font.bold: root.pulse
	}

	// The badge rides just outside the glyph's top-right corner so it reads as
	// attached to the icon rather than as another character in it. It is inset
	// by the bar's own background colour so the two never merge when the pointer
	// is over the module.
	Rectangle {
		id: dot

		visible: root.dot && !root.empty
		width: root.dotSize
		height: root.dotSize
		radius: root.dotSize / 2
		color: root.dotColor
		border.width: 1
		border.color: root.pal ? root.pal.background : "#171513"

		x: label.x + label.width - width * 0.5 - 0.5
		y: label.y - height * 0.35 + 3
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
		cursorShape: Qt.PointingHandCursor
		// Drives the tooltip. It is on the MouseArea rather than a HoverHandler
		// so there is one pointer-tracking item per module; a handler beside a
		// MouseArea tracking the same rectangle is a second thing to keep in step.
		hoverEnabled: true

		onClicked: function(mouse) {
			// The tooltip goes away on click, the way GTK's does, so it cannot end
			// up sitting over the menu the click just opened.
			tip.dismiss();
			if (mouse.button === Qt.RightButton)
				root.rightClicked();
			else
				root.clicked();
		}

		onWheel: function(wheel) {
			root.scrolled(wheel.angleDelta.y > 0 ? 1 : -1);
		}
	}

	// One tooltip per module, so it can be anchored to this module's own
	// rectangle. Hidden tooltips have no surface, so an idle bar costs nothing
	// for the dozen-odd modules that never show one.
	Tooltip {
		id: tip

		target: root
		pal: root.pal
		text: root.tooltipText
		hovered: mouse.containsMouse
	}
}
