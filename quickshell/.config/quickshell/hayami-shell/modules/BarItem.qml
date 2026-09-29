import QtQuick
import "Theme.js" as Theme

// Shared building block for every bar module.
//
// Mirrors waybar's module model so the spacing rules in style.css carry over:
// a fixed-height text cell whose width is its glyph plus explicit left/right
// margins (waybar's `margin: 0 7.5px` and friends), with an optional min-width
// so the bar does not shift when a value gains or loses a digit.
//
// It is also where the bar's edge is expressed for the modules, because `edge`
// decides the one thing every module draws: a horizontal bar runs the modules
// end to end and gives each one a line of text, a vertical one stacks them and
// gives each one a glyph above its value. The margins keep their names on both
// -- leading and trailing *along the bar* -- so `marginLeft` is the space before
// the text on a top bar and the space above the glyph on a left one.
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

	// Which edge of the screen the bar is on: "top", "bottom", "left" or
	// "right". Set by Bar.qml from BarState.position on every module.
	property string edge: "top"
	readonly property bool vertical: Theme.isVertical(edge)

	// Whether the bar is showing this module at all. Assigned from Bar.qml out
	// of the switchable set (BarState), and combined with `empty` below, so a
	// module can be hidden by the user or collapse on its own -- whichever comes
	// first -- without either one having to know about the other.
	property bool moduleShown: true

	// Whether the keyboard can land on this module when it is driving the bar
	// (see Bar.qml). True for every module there is: they all answer a click, so
	// they all answer space. It is here rather than in Bar.qml's own list because
	// it is the module that knows what it is, and a module that should be passed
	// over -- a read-out with nothing behind it -- says so once, on itself.
	property bool keyboardStop: true

	// The lines a vertical bar draws. `glyph` and `suffix` are the horizontal
	// line's two halves, so by default the vertical stack is the same two pieces
	// one above the other; a module that wants more lines overrides these.
	property string verticalGlyph: glyph.trim()
	property string verticalValue: suffix.trim()

	// An optional line drawn a quarter turn instead of stacked, for text that is
	// wider than the well can ever be: stacked, it runs off both sides of the bar,
	// and no amount of shrinking the type fixes a whole sentence. Turned, it reads
	// along the bar, where there is room for it. The clock is the one caller --
	// its whole reading is 174px at the value size, six-and-a-half wells.
	property string verticalSide: ""

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
	readonly property bool empty: vertical
		? (verticalGlyph + verticalValue + verticalSide).length === 0
		: (glyph + suffix).length === 0

	// On a vertical bar every module is the bar's well wide, so the modules line
	// up in a column, and its height is what it draws. minWidth is a horizontal
	// idea -- a floor under a text cell that gains a digit -- and has no vertical
	// counterpart, since a stacked module's height is simply its lines.
	implicitWidth: vertical
		? (empty ? 0 : Theme.verticalWell)
		: (empty ? 0 : Math.max(label.implicitWidth, minWidth) + marginLeft + marginRight + paddingLeft + paddingRight)
	implicitHeight: vertical
		? (empty ? 0 : stack.implicitHeight + marginLeft + marginRight + paddingLeft + paddingRight)
		: Theme.height

	visible: moduleShown && !empty

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

		visible: !root.vertical
		anchors.centerIn: parent
		anchors.horizontalCenterOffset: (root.marginLeft + root.paddingLeft - root.marginRight - root.paddingRight) / 2
		text: root.glyph + root.suffix
		color: root.pulse ? Theme.pulseColor : root.tint
		opacity: root.pulse ? root.pulseMix : root.dim
		font.family: root.fontFamily
		font.pixelSize: root.fontSize
		font.bold: root.pulse
	}

	// A vertical bar's module: the glyph, then the value under it. Either line may
	// be absent; the stack is whatever is left -- and a module whose reading will
	// not fit the well at all (the clock) has neither and puts its text on the
	// turned line instead. The glyph keeps the bar's type size and the value drops
	// to the smaller one, so the two read as an icon with a reading rather than as
	// two lines of text; see Theme.verticalValueSize for why the value has to shrink.
	Column {
		id: stack

		visible: root.vertical
		anchors.centerIn: parent
		anchors.verticalCenterOffset: (root.marginLeft + root.paddingLeft - root.marginRight - root.paddingRight) / 2
		spacing: 0

		Text {
			id: stackGlyph

			anchors.horizontalCenter: parent.horizontalCenter
			text: root.verticalGlyph
			// A module with no icon of its own draws its value alone rather
			// than leaving the empty line's height above it, the same way the
			// value line drops out when it has nothing to say.
			visible: text !== ""
			color: root.pulse ? Theme.pulseColor : root.tint
			opacity: root.pulse ? root.pulseMix : root.dim
			font.family: root.fontFamily
			font.pixelSize: root.fontSize
			font.bold: root.pulse
		}

		Text {
			id: stackValue

			anchors.horizontalCenter: parent.horizontalCenter
			text: root.verticalValue
			visible: text !== ""
			color: root.pulse ? Theme.pulseColor : root.tint
			opacity: root.pulse ? root.pulseMix : root.dim
			font.family: root.fontFamily
			font.pixelSize: Theme.verticalValueSize
			font.bold: root.pulse
			horizontalAlignment: Text.AlignHCenter
		}

		// The turned line. Its box is the *rotated* one -- the text's height
		// across the bar, its width along it -- because a transformed item still
		// reports its unrotated bounds to the Column above, which would otherwise
		// reserve the clock's whole 174px width inside a 26px bar. The metrics
		// are asked for outright rather than read off the Text below: a positioner
		// queries the size before the item it is sizing has laid its text out.
		Item {
			id: stackSide

			anchors.horizontalCenter: parent.horizontalCenter
			visible: root.verticalSide !== ""
			width: sideMetrics.height
			height: sideMetrics.width

			Text {
				id: stackSideText

				anchors.centerIn: parent
				text: root.verticalSide
				// A quarter turn about the item's own centre. The edge picks the
				// direction, so the text's top always faces away from the desktop:
				// bottom-to-top on a left bar, top-to-bottom on a right one, the
				// way a spine or a tab reads.
				rotation: root.edge === "right" ? 90 : -90
				color: root.pulse ? Theme.pulseColor : root.tint
				opacity: root.pulse ? root.pulseMix : root.dim
				font.family: root.fontFamily
				font.pixelSize: Theme.verticalValueSize
				font.bold: root.pulse
			}

			TextMetrics {
				id: sideMetrics

				font.family: root.fontFamily
				font.pixelSize: Theme.verticalValueSize
				text: root.verticalSide
			}
		}
	}

	// The badge rides just outside the glyph's top-right corner so it reads as
	// attached to the icon rather than as another character in it. It is inset
	// by the bar's own background colour so the two never merge when the pointer
	// is over the module.
	Rectangle {
		id: dot

		// The glyph is a line of the stacked pair on a vertical bar and the
		// whole label on a horizontal one, which is the only difference: the
		// badge stays on the icon's top-right corner either way.
		readonly property Text anchorLabel: root.vertical ? stackGlyph : label

		visible: root.dot && !root.empty
		width: root.dotSize
		height: root.dotSize
		radius: root.dotSize / 2
		color: root.dotColor
		border.width: 1
		border.color: root.pal ? root.pal.background : "#171513"

		x: anchorLabel.x + anchorLabel.width - width * 0.5 - 0.5
		y: anchorLabel.y - height * 0.35 + 3
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
		edge: root.edge
		text: root.tooltipText
		hovered: mouse.containsMouse
	}
}
