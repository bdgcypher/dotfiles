pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme.js" as Theme

// The VPN indicator's popout: which tunnel is up, and the way to hang it up.
//
// The module itself has room for a glyph and nothing else -- a 26px strip cannot
// hold a name, let alone an address -- so the panel is where the one actionable
// question about the VPN is answered: what is it, where is it, and can I drop
// it. It reads what the module already read, rather than probing a second time,
// so the icon and the panel can never disagree.
//
// Shaped like the calendar's flyout, and a layer surface for the same reason
// (see CalendarPanel and TrayExpander): a surface the compositor places has no
// parent for a grab to get refused on, its size is its content's, and it holds
// the keyboard while it is up.
Item {
	id: root

	// ── handed down by the vpn module ────────────────────────────────────────

	property var pal: null
	property string edge: "top"
	// The screen the bar is on, so the panel opens on the same monitor.
	property var screenModel: null
	// The module's own corner inside the bar's surface, and how much of the bar
	// it takes up there, so the panel centres on the module rather than hanging
	// off its leading edge. The sum Clock makes, for the same reason -- and a sum
	// of real properties rather than mapToItem(null, ...), because only a
	// property read is a dependency and a mapping would be computed once.
	property point anchor: Qt.point(0, 0)
	property size anchorSize: Qt.size(0, 0)

	// What the module last read out of vpn-status.sh.
	property bool connected: false
	property string name: ""
	property string state: ""
	property string detail: ""

	// Whether the panel is up. The module's click toggles it; the panel closes
	// itself on escape and on a click off the card, so all three write this one
	// property.
	property bool open: false

	// Emitted once the hangup has finished, so the module re-probes at once
	// instead of keeping a stale glyph for up to its whole interval.
	signal disconnected()

	// ── the palette ──────────────────────────────────────────────────────────

	readonly property bool vertical: Theme.isVertical(edge)
	readonly property color foreground: pal ? pal.foreground : "#c5c4c4"
	readonly property color background: pal ? pal.background : "#171513"
	// The accent every list in this shell marks focus with.
	readonly property color accent: pal && pal.colors && pal.colors.length > 3
		? pal.colors[3] : (pal && pal.accent ? pal.accent : "#CEA56A")
	readonly property string fontFamily: Theme.fontFamily

	// Dimmed text as a *mix towards the panel's own background* rather than
	// Qt.darker(), which only dims a light-on-dark theme. The calendar carries
	// its own copy of this (see its `shade`); it cannot live in Theme.js, which
	// is a `.pragma library` and so has no `Qt` to build a colour with.
	function shade(color, mix) {
		var b = root.background
		return Qt.rgba(color.r + (b.r - color.r) * mix,
			color.g + (b.g - color.g) * mix,
			color.b + (b.b - color.b) * mix, 1)
	}

	readonly property color dimText: shade(foreground, 0.35)
	readonly property color dimmerText: shade(foreground, 0.6)

	// ── the reading, and the one thing to do about it ────────────────────────

	// The name is the headline; with no tunnel there is nothing to name, and the
	// panel says so rather than showing an empty box -- reachable when the VPN
	// drops while the panel is up, before the module's next probe folds both of
	// them away.
	readonly property string heading: name !== "" ? name : "No VPN"
	// The address rides with the state, "Connected · 100.64.0.1", and the whole
	// line drops out when there is nothing to say.
	readonly property string detailText: state !== "" && detail !== ""
		? "· " + detail : detail
	readonly property bool hasStateLine: state !== "" || detail !== ""

	// One row, and only while there is a tunnel to hang up: a popout whose only
	// row could not do anything should not be offering one.
	readonly property var rows: connected ? ["Disconnect"] : []
	property int focusIndex: 0
	// True from the click (or space, or enter) until the script exits, so the row
	// says what it is doing and a second activation cannot queue another hangup.
	property bool working: false

	readonly property string rowLabel: working ? "Disconnecting…" : (rows.length > 0 ? rows[0] : "")

	function moveFocus(delta) {
		if (rows.length === 0)
			return
		focusIndex = Math.max(0, Math.min(rows.length - 1, focusIndex + delta))
	}

	function activate() {
		if (working || rows.length === 0)
			return
		working = true
		hangup.running = true
	}

	function dismiss() {
		open = false
	}

	Process {
		id: hangup

		command: ["bash", Quickshell.env("HOME")
			+ "/.config/quickshell/cypher-shell/scripts/vpn-disconnect.sh"]

		// The panel goes with the tunnel: whatever the script said, the reading
		// it was showing is now out of date, and the module's answer is the one
		// worth waiting for.
		onExited: {
			root.working = false
			root.open = false
			root.disconnected()
		}
	}

	// ── where the panel goes ─────────────────────────────────────────────────
	//
	// The calendar's arithmetic, because a flyout off the bar is the same
	// problem: just past the bar on the axis the bar's thickness occupies, and
	// centred on the module that opened it along the axis the bar runs -- clamped
	// so the whole card stays on screen.

	readonly property real pastBar: Theme.marginTop + Theme.thicknessFor(edge)
		+ Theme.vpnPanelBarGap
	readonly property real screenW: screenModel ? screenModel.width : 0
	readonly property real screenH: screenModel ? screenModel.height : 0

	// Where the bar's strip starts on the screen: the margin it keeps to the edge
	// it is on, and the margin at its ends.
	readonly property real barOriginX: edge === "right"
		? screenW - Theme.thicknessFor(edge) - Theme.marginTop
		: (edge === "left" ? Theme.marginTop : Theme.marginSide)
	readonly property real barOriginY: edge === "bottom"
		? screenH - Theme.thicknessFor(edge) - Theme.marginTop
		: (edge === "top" ? Theme.marginTop : Theme.marginSide)

	readonly property real followX: Math.max(Theme.marginSide,
		Math.min(barOriginX + anchor.x + anchorSize.width / 2 - cardW / 2,
			screenW - cardW - Theme.marginSide))
	readonly property real followY: Math.max(Theme.marginSide,
		Math.min(barOriginY + anchor.y + anchorSize.height / 2 - cardH / 2,
			screenH - cardH - Theme.marginSide))

	// Read once, as the panel opens, and kept while it is up -- the same call
	// CalendarPanel and TrayExpander make: the card is inside a fixed surface and
	// could follow the module, but the module drifts for reasons that have
	// nothing to do with this panel, and a card that jumped for those would be
	// the worse trade.
	property real panelX: 0
	property real panelY: 0

	function takePlace() {
		panelX = followX
		panelY = followY
	}

	// A fixed width, unlike the calendar's content-sized one: a hostname, an
	// address and a row label all change under it, and a box that resized as the
	// VPN came and went would read as the box moving rather than the reading.
	readonly property real cardW: Theme.vpnPanelWidth
	readonly property real cardH: column.implicitHeight
		+ (Theme.vpnPanelPad + Theme.vpnPanelBorderWidth) * 2
	readonly property real cardX: vertical
		? (edge === "left" ? pastBar : screenW - pastBar - cardW)
		: panelX
	readonly property real cardY: vertical
		? panelY
		: (edge === "top" ? pastBar : screenH - pastBar - cardH)

	onOpenChanged: {
		if (!open)
			return
		focusIndex = 0
		working = false
		takePlace()
		keys.forceActiveFocus()
	}

	// ── the keyboard ─────────────────────────────────────────────────────────
	//
	// What each key means while the panel is up. The handler that feeds these is
	// declared inside the panel window below, not here: a key handler only ever
	// sees the keys of the window it is declared in, and this object is declared
	// in the bar's window, which holds no keyboard at all.

	QtObject {
		id: keymap

		function handleKey(event) {
			switch (event.key) {
			case Qt.Key_Left:
			case Qt.Key_H:
			case Qt.Key_Up:
			case Qt.Key_K:
				root.moveFocus(-1)
				event.accepted = true
				break
			case Qt.Key_Right:
			case Qt.Key_L:
			case Qt.Key_Down:
			case Qt.Key_J:
				root.moveFocus(1)
				event.accepted = true
				break
			case Qt.Key_Space:
			case Qt.Key_Return:
			case Qt.Key_Enter:
				root.activate()
				event.accepted = true
				break
			}
		}
	}

	// ── the panel ────────────────────────────────────────────────────────────

	PanelWindow {
		id: panel

		screen: root.screenModel
		visible: root.open

		// Full screen, with the card drawn inside it at cardX/cardY -- the shape
		// the calendar and the notification centre use, and for the same reason:
		// a surface bigger than what it draws lets a click *off* the card put the
		// panel away, with no focus event to interpret and no second surface to
		// order against this one.
		anchors.top: true
		anchors.bottom: true
		anchors.left: true
		anchors.right: true

		exclusiveZone: 0
		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Top
		WlrLayershell.namespace: "quickshell:vpn"
		// Exclusive rather than on-demand: the panel was opened to be read and
		// acted on, so the keys belong to it until escape or a click off the card
		// takes it back.
		WlrLayershell.keyboardFocus: root.open
			? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		// Clicking anywhere the card is not puts the panel away, the way a menu
		// behaves: the click that dismisses is not passed on to what is under it.
		// Declared before the box so it stays below it, which is what keeps the
		// card's own row clickable.
		MouseArea {
			anchors.fill: parent
			onClicked: root.dismiss()
		}

		// Inside this window rather than beside the root object, because a
		// FocusScope handles the keys of the window it is declared in -- and the
		// root object's window is the bar's, which never holds them. What each key
		// means is handleKey() up by the root.
		FocusScope {
			id: keys

			anchors.fill: parent
			focus: root.open

			Keys.onEscapePressed: root.dismiss()
			Keys.onPressed: (event) => keymap.handleKey(event)
		}

		// The box, drawn the way the bar, the tooltips and the calendar draw
		// theirs: a rounded rect in the border colour with the background inset
		// inside it, because Qt centres a border pen on the item's outline and
		// clips the outer half.
		Rectangle {
			x: root.cardX
			y: root.cardY
			width: root.cardW
			height: root.cardH
			color: Theme.borderColor
			radius: Theme.vpnPanelRadius

			Rectangle {
				anchors.fill: parent
				anchors.margins: Theme.vpnPanelBorderWidth
				color: root.background
				radius: Math.max(Theme.vpnPanelRadius - Theme.vpnPanelBorderWidth, 0)
			}

			// The content, at the box's own padding inside its border.
			Column {
				id: column

				x: Theme.vpnPanelBorderWidth + Theme.vpnPanelPad
				y: Theme.vpnPanelBorderWidth + Theme.vpnPanelPad
				width: root.cardW - (Theme.vpnPanelBorderWidth + Theme.vpnPanelPad) * 2
				spacing: Theme.vpnPanelGap

				// ── the reading ──────────────────────────────────────────────
				Column {
					width: parent.width
					spacing: Theme.vpnPanelLineGap

					Text {
						id: nameText

						width: parent.width
						text: root.heading
						color: root.foreground
						font.family: root.fontFamily
						font.pixelSize: Theme.vpnPanelNameSize
						elide: Text.ElideRight
					}

					// The state, and the address it is on: one line, a dot for
					// the state itself. Laid out by hand rather than in a Row,
					// because the address has to be clipped to what is left of
					// the panel when a tailnet FQDN is longer than the box.
					Item {
						id: stateLine

						width: parent.width
						height: stateText.implicitHeight
						visible: root.hasStateLine

						Rectangle {
							id: stateDot

							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter
							width: Theme.vpnPanelDotSize
							height: Theme.vpnPanelDotSize
							radius: Theme.vpnPanelDotSize / 2
							color: root.connected ? root.accent : root.dimmerText
						}

						Text {
							id: stateText

							anchors.left: stateDot.right
							anchors.leftMargin: 7
							anchors.verticalCenter: parent.verticalCenter
							text: root.state
							color: root.dimText
							font.family: root.fontFamily
							font.pixelSize: Theme.vpnPanelStatusSize
						}

						Text {
							id: detailText

							anchors.left: stateText.right
							anchors.leftMargin: text !== "" ? 6 : 0
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							text: root.detailText
							color: root.dimmerText
							font.family: root.fontFamily
							font.pixelSize: Theme.vpnPanelStatusSize
							elide: Text.ElideRight
						}
					}
				}

				// ── the one action ───────────────────────────────────────────
				//
				// A list row rather than a button: it is the only thing here that
				// does anything, and the shell marks a focused list row with a bar
				// down its left edge -- the cue the launcher and the calendar both
				// use, at text height rather than row height.
				Item {
					id: actionRow

					width: parent.width
					height: root.rows.length > 0 ? Theme.vpnPanelRowHeight : 0
					visible: height > 0

					Rectangle {
						id: actionMark

						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: Theme.vpnPanelMarkWidth
						height: Theme.vpnPanelMarkHeight
						color: root.accent
						// The keyboard's focus and the pointer's own row get the
						// same cue, so hovering shows what a click would hit and
						// what space would fire.
						visible: actionMouse.containsMouse || root.focusIndex === 0
					}

					Text {
						id: actionText

						anchors.left: parent.left
						anchors.leftMargin: Theme.vpnPanelMarkWidth + 8
						anchors.verticalCenter: parent.verticalCenter
						text: root.rowLabel
						color: (root.focusIndex === 0 || actionMouse.containsMouse)
							? root.accent : root.foreground
						font.family: root.fontFamily
						font.pixelSize: Theme.vpnPanelStatusSize
					}

					MouseArea {
						id: actionMouse

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.activate()
					}
				}
			}
		}
	}
}
