import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The tray popout's one piece of shared state.
//
// The panel belongs to a bar and there is a bar per monitor, so TrayExpander is
// built once per screen and everything it owns -- whether it is open, which icon
// the keyboard is on -- is its own. "Open the tray" is not its own: it arrives
// from outside the shell (the launcher's System -> Setup -> System Tray entry,
// through bin/.local/bin/hayami-tray) and has to land on exactly one bar, the one
// on the screen the user is looking at. So the request is kept here, on an object
// there is one of, and every bar watches it -- the same divide BarState makes for
// the bar's own setting.
//
// The pointer never needs this: hovering the caret opens the panel on the bar it
// is hovering, which is already exactly one bar.
Item {
	id: root

	visible: false
	width: 0
	height: 0

	// ── where the request lands ──────────────────────────────────────────────

	// The screen whose tray should come out: the one the user is looking at,
	// which is where the launcher that asked for it was. Read as Hyprland's own
	// notion of the active monitor rather than from Quickshell.screens, whose
	// order says nothing about which screen has the pointer.
	readonly property string focusedMonitor: {
		var list = Hyprland.monitors.values
		for (var i = 0; i < list.length; i++) {
			if (list[i].lastIpcObject && list[i].lastIpcObject.focused)
				return list[i].name
		}
		return ""
	}

	// ── the request ──────────────────────────────────────────────────────────

	// Bumped once per request. A counter rather than a flag: asking for the tray
	// twice has to open it twice, and a flag that is already set would be a
	// request nobody saw -- the panel has no way to report that it was already
	// up, and re-asking should put the keyboard back at the first icon.
	property int requests: 0

	// The monitor whose bar answers the request above. Set before the counter is
	// bumped, so a bar reading both sees them together.
	property string monitor: ""

	function openTray() {
		var name = focusedMonitor
		if (name === "")
			return "no monitor"
		monitor = name
		requests++
		return "opened"
	}

	// ── IPC ──────────────────────────────────────────────────────────────────
	//
	// What bin/.local/bin/hayami-tray speaks to. A verb of its own rather than
	// one on the bar's handler: opening the tray is not a change to the bar's
	// settings, and hayami-bar is the command that changes those.

	IpcHandler {
		target: "tray"

		function open(): string {
			return root.openTray()
		}
	}
}
