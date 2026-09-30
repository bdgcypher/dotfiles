import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import "../modules"
import "OsdTheme.js" as Theme

// The on-screen display: one layer surface per monitor, shown on the focused one.
//
// A surface per screen, of which only the target screen's is visible, rather
// than one window moved between monitors -- because a layer surface
// cannot be moved between monitors, only re-created.
//
// Geometry, all measured off a running window (`hyprctl layers -j`):
// 292x68 logical for a volume OSD, horizontally centred, its bottom edge at 85%
// of the screen height, on the overlay layer. The width is content-sized with a
// 250px floor, which is why the same OSD is 250 wide for a one-word custom
// message and 315 for a 29-character one.
PanelWindow {
	id: osd

	required property var modelData
	required property var state
	required property var pal

	screen: modelData

	// Only the monitor hayami-osd resolved (the focused one, unless the caller
	// named another) draws the OSD.
	//
	// Compared against the screen this instance was built for rather than the
	// window's own `screen`: what this decides is whether the window is shown, and
	// the window's `screen` is managed by the shell, so reading it here fed a
	// change back into this binding and QML reported a loop for it.
	readonly property bool target: state.showing && modelData && state.monitor === modelData.name

	readonly property bool hasIcon: state.icon !== ""
	readonly property bool hasBar: state.progress >= 0

	readonly property color foreground: pal ? pal.foreground : "#c5c4c4"
	readonly property color background: pal ? pal.background : "#171513"
	// style.css: progress { background-color: @progress }, and @progress is @color6.
	readonly property color accent: (pal && pal.colors.length > Theme.fillColorIndex)
		? pal.colors[Theme.fillColorIndex] : foreground

	// The label's box is sized for "100%" itself, so the window does not resize as
	// the digits change -- measured in
	// the real font, not a pixel guess, since "100%" is four monospace characters
	// where every other percentage is three and a fixed 35px reserve once grew
	// the window exactly at full.
	TextMetrics {
		id: labelMetrics

		font.family: Theme.fontFamily
		font.pixelSize: Theme.labelSize
		text: osd.state.label
	}

	TextMetrics {
		id: maxLabelMetrics

		font.family: Theme.fontFamily
		font.pixelSize: Theme.labelSize
		text: "100%"
	}

	readonly property real labelBox: Math.max(labelMetrics.width, maxLabelMetrics.width)

	// padding + icon + gap + bar + gap + label + padding, in that order.
	// Each part contributes only when it is present, so a custom
	// message with no icon and no bar collapses to just its text.
	readonly property real contentWidth: (hasIcon ? Theme.iconBox + Theme.iconGap : 0)
		+ (hasBar ? Theme.barWidth + Theme.barGap : 0)
		+ labelBox

	readonly property real boxWidth: Math.max(Theme.minWidth,
		Math.round(contentWidth + Theme.paddingLeft + Theme.paddingRight))

	// The tallest part decides the height: 32 for an icon, the label's own line
	// height for text, and the bar on its own is only 42 (measured) -- so the
	// minimum keeps a bar-only OSD from collapsing to a sliver.
	readonly property real contentHeight: {
		var h = 0;
		if (hasIcon)
			h = Math.max(h, Theme.iconBox);
		if (state.label !== "")
			h = Math.max(h, labelMetrics.height);
		if (hasBar)
			h = Math.max(h, Theme.barHeight);
		return h;
	}

	visible: target

	anchors {
		bottom: true
		left: true
		right: true
	}

	// Bottom edge at 85% of the screen: the margin is the 15% that is left over.
	margins.bottom: Math.round(screen.height * (1 - Theme.topMargin))
	// Margins either side of a content-sized surface are how the OSD stays
	// centred as its width changes. The leftover pixel from an odd gap goes to
	// the left (292 wide on a 1745 screen: x727
	// with 726 to the right). Rounding both sides instead loses that pixel.
	readonly property real leftMargin: Math.ceil((screen.width - boxWidth) / 2)
	margins.left: leftMargin
	margins.right: screen.width - boxWidth - leftMargin

	implicitHeight: Math.max(Theme.minHeight, Math.round(contentHeight + Theme.paddingY * 2))

	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "quickshell:osd"
	// The OSD never takes focus from the window underneath it.
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

	// style.css: window { border-radius: 8px; opacity: 0.97; border: 2px solid
	// #444444; background-color: @background }
	//
	// The border is drawn the way the top bar draws its own -- a rounded rect in
	// the border colour with the background inset inside it -- because Qt centres
	// a border pen on the outline and the outer half would be clipped by the
	// surface. Insetting keeps all four sides inside.
	Rectangle {
		id: chrome

		anchors.fill: parent
		color: Theme.borderColor
		radius: Theme.radius
		// style.css: window { opacity: 0.97 }
		opacity: Theme.opacity

		Rectangle {
			anchors.fill: parent
			anchors.margins: Theme.borderWidth
			color: osd.background
			radius: Math.max(Theme.radius - Theme.borderWidth, 0)
		}

		Row {
			id: content

			// Left-anchored at the left padding, not centred: the paddings are
			// not equal (17 left, 21 right), and centring the row splits the
			// difference instead of honouring them, which pushes the icon, the
			// bar and the label about 3px right of where they should be. Anchoring
			// also matches what happens when the 250px floor is wider than the
			// content -- a box lays its children out from the left.
			anchors.left: parent.left
			anchors.leftMargin: Theme.paddingLeft
			anchors.verticalCenter: parent.verticalCenter
			spacing: 0

			// The icon's box is 32 wide (which is what sets the OSD's height) plus
			// the gap to the bar. See OsdTheme.js for the token values.
			Item {
				visible: osd.hasIcon
				implicitWidth: Theme.iconBox + Theme.iconGap
				implicitHeight: Theme.iconBox

				// Positioned against the icon's box, not centred in this item: the
				// item also carries the gap, so centring in it would push the
				// artwork half the gap to the right of where it belongs.
				SymbolicIcon {
					id: iconImage

					x: (Theme.iconBox - Theme.iconSize) / 2
					y: (Theme.iconBox - Theme.iconSize) / 2
					width: Theme.iconSize
					height: Theme.iconSize
					// Drawn in the foreground's colour, not the
					// theme's -- see SymbolicIcon.qml.
					color: osd.foreground
					source: Quickshell.iconPath(osd.state.icon, true)
				}
			}

			// The bar: a rounded trough with a rounded fill in color6. The
			// fill can exceed the trough when volume-boost has the sink above
			// 100%, so it is clamped to the bar.
			// The wrapper is a full row tall (not just the bar's 7) and the bar is
			// centred inside it. Row aligns its children to the top, so a short
			// child would otherwise ride high next to the icon.
			Item {
				visible: osd.hasBar
				implicitWidth: Theme.barWidth + Theme.barGap
				implicitHeight: Theme.iconBox

				Rectangle {
					id: bar

					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					width: Theme.barWidth
					height: Theme.barHeight
					radius: Theme.barRadius
					color: Qt.rgba(osd.foreground.r, osd.foreground.g, osd.foreground.b, Theme.troughAlpha)

					Rectangle {
						width: Math.min(parent.width, Math.max(0, osd.state.progress) * parent.width)
						height: parent.height
						radius: parent.radius
						color: osd.accent
					}
				}
			}

			Text {
				id: label

				visible: osd.state.label !== ""
				width: osd.labelBox
				height: Theme.iconBox
				// Left-aligned inside a box sized for "100%": the text starts in
				// the same place however wide it turns out. The
				// vertical alignment does the centring the Row does not.
				horizontalAlignment: Text.AlignLeft
				verticalAlignment: Text.AlignVCenter
				text: osd.state.label
				color: osd.foreground
				font.family: Theme.fontFamily
				font.pixelSize: Theme.labelSize
			}
		}
	}
}
