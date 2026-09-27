import QtQuick
import Quickshell
import "Theme.js" as Theme

// A GTK-style hover tooltip -- the standalone half of waybar's module model.
//
// waybar leans on GTK for this: a module whose text is non-empty gets a
// GtkTooltip whenever the pointer rests on it, and its only say in the looks is
// style.css's `tooltip { padding: 2px }`. The behaviour is therefore GTK's, and
// all of it is reproduced here: the delay before it appears (gtk-tooltip-delay,
// 500ms), the immediate disappearance when the pointer leaves, and the expiry
// after gtk-tooltip-timeout (5s) even if the pointer has not moved.
//
// It is a PopupWindow rather than another layer surface because that is the one
// sort of Quickshell window that can be anchored to an Item: the compositor
// places the popup against the module's own rectangle, so no coordinate has to
// be translated from the bar's surface into screen space -- which is exactly the
// arrangement a tooltip needs, and the reason waybar's own tooltips are popups.
//
// The tooltip sizes itself to its text, wrapping at tooltipMaxWidth the way GTK
// wraps long tooltips instead of running them off the edge of the screen. Text
// that already fits is never wrapped, however short it is -- see the label's
// wrapMode for why that needs saying.
PopupWindow {
	id: tip

	// The module this tooltip describes. The popup is placed against its
	// rectangle, below it.
	required property Item target

	// The bar's theme colours, handed down from the module that owns this
	// tooltip so it re-tints with the wallpaper like everything else.
	required property var pal

	// The text to show. An empty string means no tooltip at all, which is what
	// waybar's `"tooltip": false` modules amount to.
	property string text: ""

	// Whether the pointer is over the module.
	property bool hovered: false

	// GTK shows the tooltip only after a short pause, so an unhurried pointer
	// traveling across the bar does not strobe eleven of them; and once it is up
	// it is retired on its own after a few seconds.
	property bool armed: false

	readonly property bool wanted: hovered && text !== ""

	onWantedChanged: {
		if (wanted) {
			delay.restart();
			return;
		}
		delay.stop();
		expiry.stop();
		armed = false;
	}

	// A module whose text changes while hovered (an update counting down, say)
	// takes the old tooltip away rather than leaving it up with stale content.
	onTextChanged: if (!wanted) armed = false

	// GTK hides the tooltip when the module it belongs to is clicked, which is
	// what keeps it from sitting over a menu the click just opened.
	function dismiss() {
		delay.stop();
		expiry.stop();
		armed = false;
	}

	Timer {
		id: delay

		interval: Theme.tooltipDelay

		onTriggered: {
			tip.armed = true;
			expiry.restart();
		}
	}

	Timer {
		id: expiry

		interval: Theme.tooltipTimeout

		onTriggered: tip.armed = false
	}

	visible: wanted && armed
	color: "transparent"

	// The placement pair that puts a popup directly below the module, centred on
	// it: `edges` is the edge of the module's rectangle the tooltip attaches to,
	// and `gravity` is the direction it extends from there. (The two read as if
	// they should be swapped, but this is the pair a scratch shell measured as
	// landing under the anchor with its top edge flush with the anchor's bottom.)
	//
	// Anchoring to the item rather than to a coordinate is what makes this need
	// no arithmetic: the compositor knows where the module is, so the bar's
	// surface offset never has to be translated into screen space.
	anchor.item: target
	anchor.edges: Edges.Bottom
	anchor.gravity: Edges.Bottom

	// Only sliding. GTK also flips a tooltip that cannot fit below its widget,
	// but above the top bar is off-screen, so for the last row of modules a
	// flip would trade a clipped tooltip for an invisible one.
	anchor.adjustment: PopupAdjustment.Slide

	// The gap between the module and the tooltip. GTK leaves the same few pixels
	// of air, and without it the tooltip's top border would sit right against the
	// bar's own bottom border and read as part of it.
	//
	// Negative because a margin shrinks the anchor rectangle: a positive bottom
	// margin pulls the reference edge *up*, so the tooltip would climb into the
	// bar. Measured in the scratch shell before it was used here -- +10 moved the
	// popup 10px up, -10 moved it 10px down.
	anchor.margins.bottom: -Theme.tooltipGap

	// The box's own padding plus its border, on each side.
	readonly property real insetX: Theme.tooltipPaddingX + Theme.tooltipBorderWidth
	readonly property real insetY: Theme.tooltipPaddingY + Theme.tooltipBorderWidth

	// Whether the text is genuinely too wide for the cap and therefore has to be
	// broken up, as opposed to merely fitting.
	readonly property bool wrapping: label.naturalWidth > Theme.tooltipMaxWidth

	// The width of the text: exact when it fits, the cap when it does not. The
	// label measures itself -- see naturalWidth there -- so a short tooltip is
	// exactly as wide as its text and nothing more.
	readonly property real textWidth: wrapping
		? Theme.tooltipMaxWidth
		: Math.ceil(label.naturalWidth)

	// Sized to the text it just measured, so the surface is exactly the box.
	implicitWidth: Math.ceil(textWidth + insetX * 2)
	implicitHeight: Math.ceil(label.implicitHeight + insetY * 2)

	// Drawn the way the bar and the OSD draw their own borders -- a rounded rect
	// in the border colour with the background inset inside it -- because Qt
	// centres a border pen on the item's outline and clips the outer half.
	Rectangle {
		anchors.fill: parent
		color: Theme.borderColor
		radius: Theme.tooltipRadius

		Rectangle {
			anchors.fill: parent
			anchors.margins: Theme.tooltipBorderWidth
			color: tip.pal ? tip.pal.background : "#171513"
			radius: Math.max(Theme.tooltipRadius - Theme.tooltipBorderWidth, 0)
		}
	}

	Text {
		id: label

		// Placed rather than anchored: the window's size is derived from this
		// item's implicitHeight, which anchoring it to the parent would make
		// circular.
		x: tip.insetX
		y: tip.insetY

		// The text laid out unwrapped: for a single line, its true rendered
		// width; for several, that of the widest line. A Text keeps reporting
		// this even while it is wrapping over an explicit width (measured: a
		// 963px string reports 963 with a 400px width and three lines), so
		// there is no loop in binding the box back to it, and no second
		// metrics object to keep in font sync.
		//
		// This is why the label measures itself rather than a TextMetrics:
		// TextMetrics.advanceWidth is the sum of the glyph advances, which
		// omits the last glyph's right side bearing and, for multi-line text,
		// keeps summing across the lines instead of reporting the widest one.
		// Both errors were visible: a tooltip of ceil(advanceWidth) came out a
		// fraction of a pixel too narrow for its own last glyph and broke it
		// onto a line of its own ("13%" as "13" and "%"), and a two-line
		// tooltip was sized as wide as both lines side by side.
		readonly property real naturalWidth: implicitWidth

		width: tip.textWidth
		text: tip.text
		// Only wrapped when it has to be: at a width of ceil(naturalWidth) no
		// wrap is possible in principle, and saying so outright means a
		// fractional width can never push the final glyph down a line. Explicit
		// newlines still break in either mode, so a tooltip that carries its
		// own line breaks keeps them.
		wrapMode: tip.wrapping ? Text.Wrap : Text.NoWrap
		color: tip.pal ? tip.pal.foreground : "#c5c4c4"
		font.family: Theme.fontFamily
		font.pixelSize: Theme.tooltipFontSize
	}
}
