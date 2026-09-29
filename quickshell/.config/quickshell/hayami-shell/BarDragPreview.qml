import QtQuick
import Quickshell
import Quickshell.Wayland
import "modules/Theme.js" as Theme

// The ghost of the bar, drawn where the bar would land, while it is being
// dragged to another edge.
//
// One surface per monitor, of which only the one the pointer is on draws -- the
// same shape the notification popups and the OSD use, and for the same reason: a
// layer surface cannot be moved between monitors, only re-created.
//
// The ghost is the bar's own geometry rather than a freehand rectangle: the
// margins, the radius and the thickness all come from the same tokens the bar
// itself is built from, so the preview cannot promise a placement the bar does
// not take. It is drawn inside a full-screen surface because the ghost has to be
// able to sit at any of the four edges, and the surface's own local coordinates
// are the monitor's -- which is exactly what those tokens are measured in.
PanelWindow {
	id: preview

	required property var modelData
	required property var state
	required property var pal

	screen: modelData

	// Only the monitor the pointer is on draws, and only while the drag is live
	// and has settled on an edge the bar would actually move to.
	//
	// The edge the bar is already on is not a preview of anything, and drawing it
	// puts the ghost -- an accent-tinted band the bar's own length, with an accent
	// border -- directly over the bar for the first moments of every drag, before
	// the pointer has travelled anywhere. That reads as the bar flashing a colour
	// when you take hold of it, not as a preview, and it is the reason the press
	// is the one moment of the gesture with something to explain. The bar dimming
	// is the whole of what a drag on the spot looks like, and it is enough.
	readonly property bool active: state !== null && state.dragging
		&& state.target !== "" && state.target !== state.position
		&& state.monitor === modelData.name

	readonly property string edge: (state && state.target !== "") ? state.target : "top"
	readonly property bool vertical: Theme.isVertical(edge)
	readonly property real thickness: Theme.thicknessFor(edge)

	readonly property color accent: (pal && pal.colors && pal.colors.length > 3)
		? pal.colors[3] : (pal && pal.accent ? pal.accent : "#CEA56A")

	// Mapped for the shell's whole life; only what it draws is switched on and
	// off. A layer surface that is unmapped is faded out by the compositor
	// (Hyprland's fadeLayersOut, ~80ms), and that fade is the ghost's accent
	// washing over the bar it has just been replaced by -- the bar lands
	// underneath a preview that is still half there. Hidden rather than unmapped
	// it is gone within the frame the drag ends on, like everything else on the
	// bar. Idle it draws nothing at all, and `mask` keeps it out of the pointer's
	// way, so being there costs the surface and nothing else.
	visible: true
	color: "transparent"

	anchors {
		top: true
		bottom: true
		left: true
		right: true
	}

	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore

	// Above the bar, which is on the top layer.
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "quickshell:bar-preview"
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

	// No input region at all: the whole gesture belongs to the bar's own surface,
	// which holds the pointer for the length of the drag. Without this the ghost
	// would be a dead zone over the screen it covers.
	mask: Region {}

	// Where the bar would be, in this monitor's coordinates -- the mirror of what
	// Bar.qml does with its anchors and margins, and of what BarState does with
	// the pointer when it picks the nearest edge.
	Rectangle {
		id: ghost

		// The monitor the pointer is on, and only while the drag is live and has
		// settled on an edge -- see `active` above.
		visible: preview.active

		x: preview.edge === "left" ? Theme.marginTop
			: (preview.edge === "right" ? preview.width - Theme.marginTop - width : Theme.marginSide)
		y: preview.edge === "top" ? Theme.marginTop
			: (preview.edge === "bottom" ? preview.height - Theme.marginTop - height : Theme.marginSide)

		width: preview.vertical ? preview.thickness : Math.max(preview.width - Theme.marginSide * 2, 0)
		height: preview.vertical ? Math.max(preview.height - Theme.marginSide * 2, 0) : preview.thickness

		radius: Theme.dragPreviewRadius
		color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, Theme.dragPreviewFillAlpha)
		border.width: Theme.dragPreviewBorderWidth
		border.color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, Theme.dragPreviewBorderAlpha)

		// The edge it is about to land on, named, in the middle of the ghost.
		//
		// A top or bottom ghost is as wide as the screen, so its name is simply a
		// horizontal line across the middle of it. A vertical one is only 32px
		// wide -- narrower than the word that has to go in it -- so its name is
		// turned a quarter and reads *along* the ghost instead, the way the clock
		// reads along a vertical bar. Turning it is what lets the label fit: the
		// text's height is what has to fit across the ghost, not its length, and a
		// 12px line of type has room to spare in 32px.
		Text {
			id: heading

			anchors.centerIn: parent
			text: preview.edge.charAt(0).toUpperCase() + preview.edge.slice(1)
			// A quarter turn about the item's own centre, and the item is centred
			// in the ghost, so the label stays centred in it whichever way up it
			// is. The edge picks the direction, so the text's top always faces
			// away from the desktop: bottom-to-top on the left, top-to-bottom on
			// the right, as the clock's does on a vertical bar.
			rotation: !preview.vertical ? 0 : (preview.edge === "right" ? 90 : -90)
			color: preview.accent
			font.family: Theme.fontFamily
			font.pixelSize: Theme.fontSize
			font.bold: true
		}
	}
}
