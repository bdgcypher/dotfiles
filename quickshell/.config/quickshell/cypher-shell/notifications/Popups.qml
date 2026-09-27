import QtQuick
import Quickshell
import Quickshell.Wayland
import "NotifTheme.js" as Theme

// The floating notification popups. A layer surface is declared for every
// monitor, but only the one that owns the stack draws anything: swaync keeps a
// single notification window and shows it on the monitor that was focused when
// the notification arrived (its --change-noti-monitor, which would follow the
// mouse afterwards, is not implemented).
//
// Geometry, from swaync's own CSS and confirmed against the live swaync window
// with `hyprctl layers -j` plus grim crops on this 1.1-scaled screen:
//
//   cards       400 wide, flush with the right edge, from the top of the screen
//   first card  top edge 54 from the screen top (38 padding + 16 row margin)
//   card        376 wide -- the 24px row margin -- with its right edge 24 from
//               the screen edge
//   gap         16 between cards
//
// The surface itself is wider than that by Theme.popupDragRoom, which sits to
// the left of the cards purely so a popup can be dragged that way; the extra
// strip is masked out of the input region so it lets clicks through.
//
// The measured card corners: left edge at logical x 1345.5 of 1745, right edge
// 24.1 from the right, top border at logical y 53.2. A text-only card is 93 tall
// and one with a 48px icon 112, which is what NotifCard's padding arithmetic
// reproduces.
//
// ── how the animation works ──────────────────────────────────────────────────
// The stack is a `ListModel` of notification ids, and the Repeater is bound to
// it. That matters: a JS-array model is a fresh object on every change, so a
// Repeater would destroy and rebuild every delegate on each arrival -- which is
// why the whole stack used to replay its entrance together, and why a card's
// displacement had to be reconstructed from recorded geometry (which could land
// before the Column had settled the new card's height, snapping one card and
// overshooting another). `ListModel.insert`/`remove` touch only the affected
// delegates, so every other card keeps its identity and its position.
//
// With the delegates preserved, the vertical motion is just a property:
//
//   * every card's `y` comes from the Column. When it changes, the card is
//     held where it was and animated to the new place (a positioner does not
//     go through `Behavior`, so the offset is applied by hand -- see the
//     delegate). A new arrival is inserted at the front, the Column moves
//     every older card down a row, and each one *slides* to its new place --
//     one plain animation to the final position, so there is no snap and no
//     bounce. A card leaving the stack slides the gap closed the same way;
//   * only a genuinely new card plays the entrance -- slide in from the right
//     and fade, the mirror of the swipe exit -- because it is the only delegate
//     built for an id that was not already on screen;
//   * a popup that times out is left in the model one beat while it plays its
//     exit (slide out to the right, fading) and is removed afterwards.
//
// `state.popups` itself stays a plain derived JS list (the source of truth lives
// in NotifState); this window reconciles the model against it.
PanelWindow {
	id: root

	required property var modelData
	required property var state
	required property var pal

	screen: modelData

	// Whether this is the screen the popups belong to.
	//
	// Compared against the screen this instance was built for rather than the
	// window's own `screen`, because the latter is managed by the shell: reading
	// it here fed a change back into this binding (QML reported a loop for it),
	// since what this decides is whether the window is shown at all.
	readonly property bool onPopupScreen: modelData ? modelData.name === state.popupMonitor : false

	visible: root.onPopupScreen && rows.count > 0

	anchors {
		top: true
		right: true
	}

	NotifColors {
		id: colors

		pal: root.pal
	}

	implicitWidth: Theme.popupWidth + Theme.popupDragRoom
	// Fixed height for the surface's whole life. Hyprland does not repaint
	// the band a layer surface vacates when it shrinks (the old frame's pixels
	// linger until something else damages there -- a swipe-away leaves the
	// vanished card's border smearing below the survivor), and a resize can
	// flash the stack blank for a frame or two on arrival. A constant height
	// has neither problem: the surface maps once, paints only the card strip,
	// and unmaps when the stack empties -- the one transition that damages
	// cleanly. Input stays limited to the cards through the mask below.
	implicitHeight: screen ? screen.height - 8 : 600

	// Only the cards take input: the drag room to their left, the strip above
	// the first card, and everything below the stack all pass clicks through
	// -- without this the surface would be a dead zone over the screen's
	// whole right edge whenever a popup is up.
	mask: Region {
		x: Theme.popupDragRoom
		y: Theme.popupTop
		width: Theme.popupWidth
		height: stack.implicitHeight
	}

	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "quickshell:notifications"
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

	// ── the model ────────────────────────────────────────────────────────────

	// The display order, newest first: one row per popup on screen (plus any
	// popup still playing its exit). A row holds only the notification id; the
	// card looks the live notification up in `byId`.
	ListModel {
		id: rows

		dynamicRoles: true
	}

	// id -> notification, for the delegates to resolve. Filled before a row is
	// inserted, dropped with the row.
	property var byId: ({})

	// Ids playing their exit. Read by the delegates through `exitRev`, since a
	// JS object cannot be observed on its own.
	property var exitingIds: ({})
	property int exitRev: 0

	// Ids whose delegate has not been built yet, so the one that *is* built for
	// them plays the entrance. An id already on screen is by definition not in
	// here.
	property var freshIds: ({})

	// One exit animation plus a breath before the card is dropped and the stack
	// closes up.
	readonly property int exitMs: Theme.transition + 20

	readonly property var popupsNow: root.state.popups

	onPopupsNowChanged: root.reconcile()

	// ── reconciliation ───────────────────────────────────────────────────────

	function rowIndex(id) {
		for (var i = 0; i < rows.count; i++)
			if (rows.get(i).nid === id)
				return i;
		return -1;
	}

	function isTracked(id) {
		var tracked = root.state.tracked;
		for (var i = 0; i < tracked.length; i++)
			if (tracked[i].id === id)
				return true;
		return false;
	}

	// Brings the model in line with `popups`: new arrivals go in at the front,
	// popups that dropped out are marked exiting (or dropped outright when the
	// notification is gone for good), and everything else is left alone so its
	// delegate -- and its animation -- survives.
	function reconcile() {
		// Every popup that is not already a row is new; insert them newest
		// first, i.e. walking the list backwards and pushing onto the front.
		for (var p = root.popupsNow.length - 1; p >= 0; p--) {
			var n = root.popupsNow[p];
			if (root.rowIndex(n.id) >= 0)
				continue;
			root.byId[n.id] = n;
			root.freshIds[n.id] = true;
			rows.insert(0, { "nid": n.id });
		}

		// A row that is no longer popping has timed out (still tracked: keep it
		// a beat for the exit) or been dismissed (gone from tracked: its own
		// swipe flight has already carried it off screen, so drop it at once).
		for (var i = rows.count - 1; i >= 0; i--) {
			var id = rows.get(i).nid;
			var popping = false;
			for (var q = 0; q < root.popupsNow.length; q++) {
				if (root.popupsNow[q].id === id) {
					popping = true;
					break;
				}
			}
			if (popping)
				continue;

			if (root.isTracked(id))
				root.markExiting(id);
			else
				root.removeRow(id);
		}
	}

	// Flags a row for its exit. The delegate picks it up through `exitRev` and
	// plays the slide-and-fade; the row is then dropped, which is what lets the
	// Column close the gap.
	function markExiting(id) {
		if (root.exitingIds[id] === true)
			return;
		root.exitingIds[id] = true;
		root.exitRev++;
		root.dropLater(id);
	}

	function dropLater(id) {
		var t = Qt.createQmlObject('import QtQuick 2.0\nTimer { }', root);
		t.interval = root.exitMs;
		t.repeat = false;
		t.triggered.connect(function() {
			t.destroy();
			root.removeRow(id);
		});
		t.start();
	}

	function removeRow(id) {
		var idx = root.rowIndex(id);
		if (idx >= 0)
			rows.remove(idx);
		delete root.exitingIds[id];
		delete root.byId[id];
		delete root.freshIds[id];
		root.exitRev++;
	}

	// Older notifications are scrolled out of the way rather than clipped: with
	// enough notifications on screen the stack is taller than the monitor.
	Flickable {
		id: flick

		anchors.top: parent.top
		anchors.topMargin: Theme.popupTop
		anchors.left: parent.left
		anchors.right: parent.right
		height: Math.min(stack.implicitHeight, parent.height - Theme.popupTop)
		contentHeight: stack.implicitHeight
		interactive: contentHeight > height
		// Clip only when the stack actually overflows the window and the
		// Flickable has something to scroll: while cards are displacing, a
		// card sits up to a row-height below the stack's final bottom edge,
		// and an always-on clip slices its lower border off mid-animation
		// (the bottom cut on the third and later popups). The window is
		// full-height, so an unclipped stack just paints into empty space.
		clip: contentHeight > height
		boundsBehavior: Flickable.StopAtBounds

		Column {
			id: stack
			objectName: "popupStack"

			// The cards keep the 400-wide strip against the screen's right edge;
			// the window's own extra width is drag room and nothing else.
			x: Theme.popupDragRoom
			width: Theme.popupWidth
			spacing: Theme.popupRowGap

			Repeater {
				// Empty on every monitor but the one that owns the stack, so
				// that no other screen arms a second copy of these timeouts.
				model: root.onPopupScreen ? rows : []

				delegate: Item {
					id: slot

					readonly property string nid: model.nid
					readonly property var notification: root.byId[slot.nid]
					// Read through `exitRev` so marking the id is seen.
					readonly property bool exiting: {
						root.exitRev;
						return root.exitingIds[slot.nid] === true;
					}
					property bool exitStarted: false

					width: stack.width
					height: card.height

					property bool placed: false
					property real lastY: 0

					// The cards below slide down (or up) to their new place when the
					// Column moves them. A positioner does not go through `Behavior`,
					// so the motion is driven here: on every `y` change the card is
					// held where it was and `shift.y` is animated back to zero. One
					// animation to the final position -- no snap, no overshoot, no
					// bounce -- and a later layout correction simply resumes from
					// wherever the card has got to. The entrance and exit own
					// `shift.x`, so the two axes never fight.
					onYChanged: {
						if (!slot.placed)
							return;
						var delta = slot.y - slot.lastY;
						slot.lastY = slot.y;
						if (Math.abs(delta) < 0.5)
							return;
						shift.y -= delta;
						displace.restart();
					}

					transform: Translate {
						id: shift
					}

					// The displacement: from wherever the card sat before the Column
					// moved it to wherever it sits now.
					NumberAnimation {
						id: displace

						target: shift
						property: "y"
						to: 0
						duration: Theme.transition
						easing.type: Easing.OutCubic
					}

					NotifCard {
						id: card

						width: stack.width - Theme.popupRowRight

						notification: slot.notification
						notifColors: colors
						state: root.state
						popup: true
					}

					// transition-time: 200 -- swaync slides a popup in from
					// the right and fades it in.
					NumberAnimation {
						id: slideIn

						target: shift
						property: "x"
						to: 0
						duration: Theme.transition
						easing.type: Easing.OutCubic
					}

					NumberAnimation {
						id: fadeIn

						target: slot
						property: "opacity"
						to: 1
						duration: Theme.transition
						easing.type: Easing.OutCubic
					}

					// The exit: slide out to the right, fading -- the mirror
					// of the entrance, and the same animation a manual swipe
					// gets.
					NumberAnimation {
						id: slideOut

						target: shift
						property: "x"
						to: card.width + Theme.dragExitOvershoot
						duration: Theme.transition
						easing.type: Easing.OutCubic
					}

					NumberAnimation {
						id: fadeOut

						target: slot
						property: "opacity"
						to: 0
						duration: Theme.transition
						easing.type: Easing.OutCubic
					}

					Component.onCompleted: {
						slot.placed = true;
						slot.lastY = slot.y;
						if (slot.exiting) {
							slot.beginExit();
							return;
						}

						if (root.freshIds[slot.nid] === true) {
							// A genuinely new notification: the only thing
							// that plays the entrance.
							delete root.freshIds[slot.nid];
							shift.x = card.width + Theme.dragExitOvershoot;
							slot.opacity = 0;
							slideIn.start();
							fadeIn.start();
						}
					}

					onExitingChanged: {
						if (slot.exiting)
							slot.beginExit();
					}

					function beginExit() {
						if (slot.exitStarted)
							return;
						slot.exitStarted = true;
						slideIn.stop();
						fadeIn.stop();
						slideOut.start();
						fadeOut.start();
					}
				}
			}
		}
	}
}
