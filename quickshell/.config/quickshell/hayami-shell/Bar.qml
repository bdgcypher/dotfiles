import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "modules"
import "modules/Theme.js" as Theme

// The bar itself.
//
// Geometry comes straight from waybar's config.jsonc ("height": 26,
// "margin": "6 12 0 12") and style.css (#waybar: 8px radius, 1.2px #444444
// border, 0.9 opacity), so swapping between the two bars moves nothing.
//
// Like waybar's "exclusive": false, the panel reserves no screen space
// (exclusiveZone 0 / ExclusionMode.Ignore): windows are free to use the strip
// behind the bar, and the rounded corners float over the desktop.
//
// ── any edge ────────────────────────────────────────────────────────────────
//
// The bar is on whichever edge BarState.position names. Top and bottom are the
// bar this has always been, mirrored; left and right turn the same three module
// groups through a quarter, so the bar's 26px height becomes its thickness and
// the modules stack down the screen (see BarGroup and BarItem for how the
// modules themselves follow).
//
// The margins keep their names on every edge: `marginTop` is the gap to the edge
// the bar is on, `marginSide` the gap at its two ends. The edge picks which way
// round they are spent; nothing else about the window changes with it.
//
// ── moving it ───────────────────────────────────────────────────────────────
//
// Pressing the bar's own background and releasing on another edge moves it
// there; see BarState for the gesture and BarDragPreview for what is drawn while
// it is live. The background is the drag handle, so the modules keep every click
// they had -- the press is only the bar's if none of them took it.
PanelWindow {
	id: bar

	required property var modelData
	screen: modelData

	// The shell's notification server, so the bell reads its state directly
	// instead of shelling out to swaync-client.
	property var notifications: null

	// Where the bar is and what it shows, shared by every monitor's bar.
	property var state: null

	// The tray popout's shared request, so the launcher can ask for the tray by
	// name and have it come out of this bar rather than of all of them at once.
	property var tray: null

	readonly property string edge: state ? state.position : "top"
	readonly property bool vertical: Theme.isVertical(edge)
	readonly property bool dragging: state !== null && state.dragging

	// Whether this is the bar the keyboard is pointed at. The mode itself is one
	// flag for the whole shell (BarState.keyboardMode); which bar answers it is
	// this, and only one bar is on the focused monitor -- so exactly one surface
	// ever asks the compositor for the keys.
	//
	// Hyprland's own notion of the focused monitor, asked the way TrayState asks
	// it: Quickshell.screens is in the compositor's order, which says nothing
	// about which screen has the focus.
	readonly property bool onFocusedMonitor: {
		var list = Hyprland.monitors.values
		for (var i = 0; i < list.length; i++) {
			if (list[i].lastIpcObject && list[i].lastIpcObject.focused
					&& list[i].name === modelData.name)
				return true
		}
		return false
	}

	readonly property bool keyboard: state !== null && state.keyboardMode && onFocusedMonitor

	// The accent every list in this shell marks focus with: @color3 when the
	// palette has it, otherwise the palette's own accent.
	readonly property color accent: pal && pal.colors && pal.colors.length > 3
		? pal.colors[3] : (pal ? pal.accent : "#CEA56A")

	// ── one surface, the whole screen ────────────────────────────────────────
	//
	// The surface is the monitor on every edge and at every moment. Where the bar
	// is drawn inside it is `strip`; how much of it takes input is `mask`. Those
	// are the two things that change as the bar moves, and nothing else does.
	//
	// A surface only as big as the bar was the obvious geometry, and it is what
	// this used to be: the anchors put it at its edge and the bar filled it. Two
	// things make the constant screen the better shape, both of them measured on
	// the running shell rather than settled by argument.
	//
	// One is the gesture. The compositor hands this window a release the moment
	// the pointer leaves the surface, so a press does not survive being dragged off
	// the bar -- and a drag is nothing *but* leaving the bar. The bar is 26px of a
	// 982px screen and the edge being picked is out past that, so with the surface
	// only as big as the bar the drag died about a frame after it started:
	// measured, one sample recorded, no travel, `moved` false, the bar back where
	// it was. A surface the pointer cannot leave is what the gesture needs; the
	// input region is what keeps that surface a bar to everything else.
	//
	// The other is what a resize costs. A layer surface that changes size is
	// reconfigured, and until this client commits a buffer for the new size the
	// compositor paints the old buffer stretched into the new geometry. A 26px bar
	// stretched over the screen is a wash of the bar's own pixels: measured, the
	// whole display dropping a fifth of its contrast (45 to 55 mean brightness
	// with the detail gone) for two frames at the moment a drag began, and the
	// same thing in miniature every time the bar moved to another edge -- that one
	// is what hypr/apps/bar.lua's no_anim was for. A surface that never resizes has
	// neither problem, and the bar moving between edges no longer resizes anything.
	//
	// Nothing else moves with it: the reserved space is the gaps script's, the
	// ghost is the preview surface's own, and the bar is drawn exactly where it was.
	anchors {
		top: true
		bottom: true
		left: true
		right: true
	}

	// Input: the bar's own strip, and the whole screen for as long as a drag is
	// live -- the pointer cannot leave an input region that covers the screen, so
	// the press that started the gesture survives it. Same shape the notification
	// popups use: a surface bigger than what it draws, with a mask deciding where
	// it is a surface at all.
	mask: Region {
		x: bar.dragging ? 0 : bar.strip.x
		y: bar.dragging ? 0 : bar.strip.y
		width: bar.dragging ? bar.width : bar.strip.width
		height: bar.dragging ? bar.height : bar.strip.height
	}

	// Where the bar is drawn inside the surface -- the one thing about the bar's
	// geometry that changes as it moves, and where its margins are spent: the
	// surface is the screen, so `marginTop` is the gap to the edge the bar is on
	// and `marginSide` the gap at its two ends, on every edge.
	//
	// The two items below read this rather than hanging off the surface's own
	// edges, which is what keeps the bar its own size while the surface is a whole
	// screen.
	readonly property rect strip: {
		var thick = vertical ? Theme.verticalThickness : Theme.height
		if (edge === "bottom")
			return Qt.rect(Theme.marginSide, height - Theme.marginTop - thick,
				width - Theme.marginSide * 2, thick)
		if (edge === "left")
			return Qt.rect(Theme.marginTop, Theme.marginSide,
				thick, height - Theme.marginSide * 2)
		if (edge === "right")
			return Qt.rect(width - Theme.marginTop - thick, Theme.marginSide,
				thick, height - Theme.marginSide * 2)
		return Qt.rect(Theme.marginSide, Theme.marginTop, width - Theme.marginSide * 2, thick)
	}

	// ── the keyboard ─────────────────────────────────────────────────────────
	//
	// What the bar does when it holds the keys (BarState.keyboardMode). The
	// modules are what it moves between, and the order is the bar's own draw
	// order, read out of the three groups rather than kept as a second list: a
	// module added, removed or moved below is followed with nothing to keep in
	// step. Each module's `visible` is read while the binding evaluates, so one
	// appearing or going away (an update countdown starting, the VPN glyph with a
	// tunnel up) re-makes the list.

	readonly property var stops: bar.collectStops()

	function collectStops() {
		var out = []
		var groups = [left, center, right]
		for (var g = 0; g < groups.length; g++) {
			var kids = groups[g].children
			for (var i = 0; i < kids.length; i++) {
				var kid = kids[i]
				if (kid && kid.keyboardStop === true && kid.visible === true)
					out.push(kid)
			}
		}
		return out
	}

	// Where in that list the keyboard is. Reset on every entry rather than
	// remembered: the list is not the same list it was last time, and an index
	// kept from then would land on whatever now happens to be at that place.
	property int focusIndex: 0
	readonly property Item focusedStop: (focusIndex >= 0 && focusIndex < stops.length)
		? stops[focusIndex] : null

	onKeyboardChanged: {
		focusIndex = 0
		if (keyboard)
			keys.forceActiveFocus()
	}

	function moveFocus(delta) {
		if (stops.length === 0)
			return
		var next = focusIndex + delta
		if (next < 0)
			next = stops.length - 1
		else if (next >= stops.length)
			next = 0
		focusIndex = next
	}

	// What space and enter do: the module's own click, so the keyboard and the
	// pointer end in the same place. The bar lets go of the keyboard as it
	// activates rather than after: a module may open a panel -- the launcher, the
	// calendar, the tray -- and that panel takes the keys itself, which two
	// surfaces cannot ask for at once without one of them losing. The cost is that
	// the plain actions leave keyboard mode too (mute, a workspace), and nothing
	// on this side of the click can tell the two apart.
	function activateFocused() {
		var stop = focusedStop
		if (stop === null)
			return
		leaveKeyboard()
		stop.clicked()
	}

	// `r`: the module's other action, which the pointer reaches by right-clicking
	// it -- the mixer, do-not-disturb, the power profile.
	function contextFocused() {
		var stop = focusedStop
		if (stop === null)
			return
		leaveKeyboard()
		stop.rightClicked()
	}

	function leaveKeyboard() {
		if (state !== null)
			state.setKeyboardMode(false)
	}

	// What each key means, fed by the FocusScope above: a key handler only ever
	// sees the keys of the window it is declared in. The meanings stay readable on
	// their own this way, which is the split the calendar records.
	QtObject {
		id: keymap

		function handleKey(event) {
			switch (event.key) {
			case Qt.Key_Left:
			case Qt.Key_H:
			case Qt.Key_Up:
			case Qt.Key_K:
				bar.moveFocus(-1)
				event.accepted = true
				break
			case Qt.Key_Right:
			case Qt.Key_L:
			case Qt.Key_Down:
			case Qt.Key_J:
				bar.moveFocus(1)
				event.accepted = true
				break
			// Tab and shift-tab walk the same list: a row of controls is usually
			// reachable that way too, and here the row is the whole bar.
			case Qt.Key_Tab:
				bar.moveFocus(1)
				event.accepted = true
				break
			case Qt.Key_Backtab:
				bar.moveFocus(-1)
				event.accepted = true
				break
			case Qt.Key_Space:
			case Qt.Key_Return:
			case Qt.Key_Enter:
				bar.activateFocused()
				event.accepted = true
				break
			}
			if (event.accepted)
				return
			if (event.text === "r") {
				bar.contextFocused()
				event.accepted = true
			}
		}
	}

	// The anchors above size the surface to the monitor both ways, so there is no
	// implicit size left to declare: the bar's own thickness is `strip`'s business
	// now, not the window's.
	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Top
	WlrLayershell.namespace: "quickshell:bar"
	// None: the bar never takes keyboard focus away from the focused window.
	// None until the bar is asked to take it (BarState.keyboardMode): the bar
	// never takes the keyboard away from the focused window on its own account.
	WlrLayershell.keyboardFocus: bar.keyboard
		? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

	// Named BarPalette, not Palette: QtQuick already exports a Palette type.
	BarPalette {
		id: pal
	}

	// The bar's keyboard, while it has one. `focus` follows keyboard mode, so the
	// scope is armed only when the bar was asked to take the keys; what each key
	// means is handleKey() on the keymap below. A FocusScope inside the window
	// rather than handlers on the window itself, which is the shape the calendar
	// and the notification centre use.
	FocusScope {
		id: keys

		anchors.fill: parent
		focus: bar.keyboard

		Keys.onEscapePressed: bar.leaveKeyboard()
		Keys.onPressed: (event) => keymap.handleKey(event)
	}

	// Is this module switched on? A module with no key is always on, so the
	// switchable set is declared in BarState rather than here.
	function shownKey(key) {
		return state === null ? true : state.shown(key);
	}


	// The visible bar. waybar sets opacity on #waybar itself, which fades its
	// children too, so the chrome and the modules inside it share one opacity.
	//
	// The border is drawn as a rounded rect in the border colour with the
	// background inset inside it, rather than with Rectangle.border: Qt centres a
	// border pen on the item's outline, so the half of it that falls outside the
	// surface is clipped. At 1.2px that left one row of border at the top edge and
	// none at the bottom. Insetting keeps all four sides inside the surface.
	Rectangle {
		id: chrome

		// The bar's strip within the surface, not the surface itself.
		x: bar.strip.x
		y: bar.strip.y
		width: bar.strip.width
		height: bar.strip.height
		color: Theme.borderColor
		radius: Theme.radius
		// Dimmed while it is being dragged, so the bar reads as the thing in hand
		// and the ghost shows where it will land.
		opacity: Theme.barOpacity * (bar.dragging ? Theme.dragDim : 1)

		Rectangle {
			id: chromeFill

			anchors.fill: parent
			// The same band on all four sides. It used to need one more pixel at the
			// bottom than elsewhere: the layer surface came back about a physical
			// pixel short at its bottom edge, which ate into the bar when the bar
			// itself stood against that edge. That pixel is lost at the bottom of
			// the *surface*, and the surface is the whole screen now, so it lands
			// out in the empty margin below the bar rather than on the bar.
			anchors.topMargin: Theme.borderWidth
			anchors.leftMargin: Theme.borderWidth
			anchors.rightMargin: Theme.borderWidth
			anchors.bottomMargin: Theme.borderWidth
			color: pal.background
			radius: Math.max(Theme.radius - Theme.borderWidth, 0)
		}

		// The drag handle: the bar's own background, under the modules, so a press
		// that lands on a module is still the module's. What is left over is the
		// run of empty bar between the three groups, which on this bar is most of
		// its length. The open hand is the only hint that it moves; over a module
		// the module's own pointer cursor takes over.
		MouseArea {
			id: dragArea

			anchors.fill: parent
			acceptedButtons: Qt.LeftButton
			// The closed hand is the only cue, and only while the drag is live: a
			// grabby pointer over the bar's empty stretch would promise a drag
			// before anything has been pressed.
			cursorShape: bar.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

			onPressed: if (bar.state)
				bar.state.beginDrag()
			onReleased: if (bar.state)
				bar.state.endDrag()
			onCanceled: if (bar.state)
				bar.state.cancelDrag()
		}

		Item {
			// The bar's strip, inset from its ends by the modules' own padding --
			// the same inset the anchors used to carry.
			//
			// Coordinates here are the chrome's, not the surface's: this item is
			// the chrome's child and the chrome already stands at `strip`, so the
			// strip's own x/y are spent by the time they would be read. Adding
			// them again puts every module at twice the margin -- on a top bar
			// 12px in and 6px down, which is a sixth of the bar's height and
			// reads as the contents sitting low in it; on a bottom or right bar
			// the same sum lands them off the surface altogether, at 950+950 of a
			// 982px screen, so the bar comes out empty. It is the same mistake the
			// chrome's own geometry had, one level down.
			x: bar.vertical ? 0 : Theme.sectionPadding
			y: bar.vertical ? Theme.sectionPadding : 0
			width: Math.max(bar.strip.width - (bar.vertical ? 0 : Theme.sectionPadding * 2), 0)
			height: Math.max(bar.strip.height - (bar.vertical ? Theme.sectionPadding * 2 : 0), 0)

			// modules-left -- the first group along the bar: the left end when the
			// bar is horizontal, the top when it is vertical.
			//
			// The three groups are placed by x/y rather than by anchors, because
			// which anchors they need depends on the edge and an anchor that is
			// switched off is not switched off: assigning `undefined` to it leaves
			// the one from the other orientation in place, so the group ends up
			// anchored to two edges at once. A pair of expressions has no such
			// history -- "the near end of the bar's length, centred across it" is
			// the same sentence on either axis, and this is it spelled out.
			BarGroup {
				id: left

				vertical: bar.vertical

				x: bar.vertical ? (parent.width - width) / 2 : 0
				y: bar.vertical ? 0 : (parent.height - height) / 2

				MenuButton {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("menu")
				}
				Workspaces {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("workspaces")
				}
				LayoutIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("layout")
				}
				TilingDirection {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("tiling")
				}
			}

			// modules-center -- centred on the bar, not on the leftover space.
			BarGroup {
				id: center

				vertical: bar.vertical

				x: (parent.width - width) / 2
				y: (parent.height - height) / 2

				Clock {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("clock")
					state: bar.state
					screenModel: bar.modelData
				}
				Updates {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("updates")
				}
				Voxtype {
					pal: pal
					edge: bar.edge
				}
				RecordingIndicator {
					pal: pal
					edge: bar.edge
				}
			}

			// modules-right -- the last group along the bar.
			BarGroup {
				id: right

				vertical: bar.vertical

				// The far end of the bar's length, centred across it.
				x: bar.vertical ? (parent.width - width) / 2 : parent.width - width
				y: bar.vertical ? parent.height - height : (parent.height - height) / 2

				TrayExpander {
					pal: pal
					edge: bar.edge
					screenModel: bar.modelData
					moduleShown: bar.shownKey("tray")
					trayState: bar.tray
				}
				BluetoothIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("bluetooth")
				}
				NetworkIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("network")
				}
				VpnIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("vpn")
					screenModel: bar.modelData
				}
				VolumeIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("volume")
				}
				MemoryIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("memory")
				}
				CpuIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("cpu")
				}
				NotificationIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("notifications")
					state: bar.notifications
				}
				BatteryIndicator {
					pal: pal
					edge: bar.edge
					moduleShown: bar.shownKey("battery")
				}
			}

			// The focus ring: where the keyboard is, drawn around the module it is
			// on. The "outline the thing you would press" cue the notification cards
			// and the panel buttons use, in the accent the lists use.
			//
			// Placed from the focused module's own position in its group plus the
			// group's position here -- a sum of live properties rather than a mapped
			// point, because only a property read is a dependency (see the clock's
			// anchor). Declared after the three groups, so it draws over them.
			Rectangle {
				readonly property Item stop: bar.focusedStop

				visible: bar.keyboard && stop !== null
				x: stop ? stop.parent.x + stop.x - Theme.barFocusInset : 0
				y: stop ? stop.parent.y + stop.y - Theme.barFocusInset : 0
				width: stop ? stop.width + Theme.barFocusInset * 2 : 0
				height: stop ? stop.height + Theme.barFocusInset * 2 : 0
				color: "transparent"
				border.width: Theme.barFocusBorderWidth
				border.color: bar.accent
				radius: Theme.barFocusRadius
			}
		}
	}
}
