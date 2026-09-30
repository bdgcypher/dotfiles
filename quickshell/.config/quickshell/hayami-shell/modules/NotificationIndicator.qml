import QtQuick
import "Icons.js" as Icons

// custom/notification -- the bell.
//
// The shell owns the notification server, so there is nothing to ask: the state
// object the server lives on is handed down from
// shell.qml, and alt is read straight off it. The values are the usual
// (none / notification / dnd-none / dnd-notification / inhibited-none /
// inhibited-notification).
//
// Recolouring the whole bell (as a stylesheet rule on
// #custom-notification.active did) is not done; the bell here stays in the
// bar's own foreground colour and unread notifications are shown by a red dot on
// its corner instead. The colour is now the plain foreground in every state; the
// glyph still carries the rest of the meaning (sleeping bell, off bell, cancelled
// bell), and the dot only says "there is something waiting". Do-not-disturb
// deliberately suppresses the dot rather than adding one of its own.
//
BarItem {
	id: root

	property var state: null

	readonly property string alt: state ? state.alt : "none"
	readonly property bool active: alt.indexOf("notification") >= 0
	// Do-not-disturb suppresses the unread dot: the off bell is the whole story
	// then, and the notifications are being held rather than offered.
	readonly property bool dnd: alt.indexOf("dnd") >= 0

	glyph: iconFor(alt)
	tint: pal ? pal.foreground : "#c5c4c4"
	dot: active && !dnd

	// custom/notification: "tooltip": true. The same sentence is a property of the state
	// object, so the bell and the client report one wording.
	tooltipText: state ? state.tooltip : ""

	// style.css: #custom-notification { min-width: 12px; margin: 0 5px }. The
	// min-width carries over; the 5px margin becomes the cluster's margin, so the
	// steps around the bell match the ones around the other indicators.
	minWidth: 12
	marginLeft: 6
	marginRight: 6

	// Left click opens the control centre, right click toggles do-not-disturb --
	// matching the two on-click bindings this module has always had.
	onClicked: {
		if (root.state)
			root.state.togglePanel();
	}
	onRightClicked: {
		if (root.state)
			root.state.toggleDnd();
	}

	// The eight alt values and the glyphs picked for them --
	// including the two combination states, where the *inhibited* glyph is the one
	// shown. The one exception is the plain "notification" state, which would
	// otherwise use the bell_badge glyph and double up with the dot this bar draws.
	function iconFor(state) {
		if (state === "notification")
			return Icons.notifActive;
		if (state === "dnd-notification")
			return Icons.notifDndActive;
		if (state === "dnd-none")
			return Icons.notifDndNone;
		if (state === "inhibited-notification" || state === "dnd-inhibited-notification")
			return Icons.notifInhActive;
		if (state === "inhibited-none" || state === "dnd-inhibited-none")
			return Icons.notifInhNone;
		return Icons.notifNone;
	}
}
