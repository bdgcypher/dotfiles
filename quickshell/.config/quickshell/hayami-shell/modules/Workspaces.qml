// The delegate below reads the outer `root` id, which under QML 6 semantics
// requires the Bound component behaviour (delegates are otherwise compiled with
// their own context and Qt warns about it).
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import "Icons.js" as Icons
import "Theme.js" as Theme

// hyprland/workspaces.
//
// Matches the waybar module:
//   * workspace 1 is always shown ("persistent-workspaces": {"1": []})
//   * the focused workspace shows the filled glyph, the rest show their number
//     ("format-icons".active)
//   * workspaces with no windows dim to 0.5 (#workspaces button.empty)
//   * left click activates the workspace ("on-click": "activate")
//
// A Grid rather than a Row, because the digits have to run down the bar when the
// bar is on a left or right edge. `rows: 1` is a Row and `columns: 1` is a
// Column, so one positioner covers both and the delegates below are unchanged --
// waybar's own vertical bars do the same thing with the same module.
Grid {
	id: root

	property var pal
	property string edge: "top"

	// Whether the bar is showing the workspace numbers at all. This is a Grid
	// rather than a BarItem, so it carries its own copy of the switch the modules
	// get from BarItem -- the key is still BarState's, in Bar.qml, and this is only
	// what it lands on.
	property bool moduleShown: true

	// The bar's keyboard (Bar.qml) moves between the modules that say they are a
	// stop. Being a Grid rather than a BarItem, this has to say it itself, the
	// same way it carries `moduleShown` above.
	property bool keyboardStop: true

	// The row is one stop, not one per digit: what a keyboard parked on the
	// workspaces is reaching for is the overview -- the same thing SUPER + TAB
	// opens (bindings/tiling.lua) -- rather than one particular number. The
	// pointer still picks a number, on the single digits below.
	//
	// Hyprland here is Lua-configured, so a plugin call goes out as Lua, exactly
	// the way the workspace clicks below dispatch theirs.
	signal clicked()

	onClicked: Hyprland.dispatch('hl.plugin.scrolloverview.overview("toggle all")')

	// Nothing is bound to the other action -- a number is not something you can
	// right-click -- but Bar.qml's `r` calls it, and calling a signal this object
	// does not have is a TypeError rather than a quiet no-op.
	signal rightClicked()

	readonly property bool vertical: edge === "left" || edge === "right"

	// No implicit size is assigned: a positioner computes its own from its
	// children, and assigning one is a read-only property error at load time. The
	// group above skips an invisible child, so hiding this is enough.
	visible: moduleShown

	rows: vertical ? -1 : 1
	columns: vertical ? 1 : -1

	// style.css: #workspaces button { padding: 0 6px; margin: 0 1.5px }. Both live on
	// the delegate: the 6px padding, and the two 1.5px margins that already meet
	// between neighbours. Spacing here would add a third gap waybar does not have.
	spacing: 0

	function wsFor(id) {
		var list = Hyprland.workspaces.values;
		for (var i = 0; i < list.length; i++) {
			if (list[i].id === id)
				return list[i];
		}
		return null;
	}

	// Workspace 1 plus every workspace that currently exists, deduplicated.
	function ids() {
		var out = [1];
		var list = Hyprland.workspaces.values;
		for (var i = 0; i < list.length; i++) {
			var id = list[i].id;
			if (id > 0 && id !== 1)
				out.push(id);
		}
		out.sort(function(a, b) {
			return a - b;
		});
		return out;
	}

	function isActive(id) {
		var focused = Hyprland.focusedWorkspace;
		return focused !== null && focused.id === id;
	}

	// waybar: "format-icons" -> { "1": "1", ..., "9": "9", "10": "0" }. The tenth
	// workspace shows a bare 0 so the row stays one character wide.
	function iconFor(id) {
		if (root.isActive(id))
			return Icons.wsActive;
		return id === 10 ? "0" : String(id);
	}

	function isEmpty(id) {
		var ws = root.wsFor(id);
		if (ws === null)
			return true;

		// lastIpcObject is the raw hyprctl workspace object, so this is the same
		// "windows" count waybar reads.
		var raw = ws.lastIpcObject;
		if (raw && raw.windows !== undefined)
			return raw.windows === 0;

		return ws.toplevels.values.length === 0;
	}

	Repeater {
		model: root.ids()

		delegate: BarItem {
			required property var modelData

			pal: root.pal
			edge: root.edge
			glyph: root.iconFor(modelData)
			minWidth: 9
			marginLeft: 1.5
			marginRight: 1.5
			// style.css: #workspaces button { padding: 0 6px }
			paddingLeft: 6
			paddingRight: 6
			// waybar renders these in GTK's default font, because `#workspaces button
			// { all: initial }` throws away the font `*` sets. That is an accident of
			// that rule, not a design choice, so the digits stay in the bar's own font
			// here -- one font across the whole bar.
			dim: root.isActive(modelData) ? 1.0 : (root.isEmpty(modelData) ? Theme.dimEmpty : 1.0)

			// This machine runs Hyprland 0.56, which is Lua-configured, so the legacy
			// "workspace N" dispatch string is wrapped as hl.dispatch(workspace N) -- not
			// valid Lua, which made the click fail silently (the reply is an error, but
			// fire-and-forget IPC has nowhere to surface it). The Lua dispatcher form is
			// what the rest of the dotfiles use; see bindings/tiling.lua, which switches
			// workspaces with exactly this call.
			onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + modelData + " })")

			// The wheel steps to the neighbouring number on the bar. `ids()` is
			// sorted, so the neighbour that reads as "next" is the next entry in
			// it, and the step wraps at both ends rather than dead-ending. waybar
			// had no scroll here; this is the bar's own hook, and the same gesture
			// the volume pill already answers to.
			onScrolled: function(delta) {
				var list = root.ids();
				var at = list.indexOf(modelData);
				if (at < 0)
					return;
				var next = list[(at + (delta > 0 ? 1 : -1) + list.length) % list.length];
				Hyprland.dispatch("hl.dsp.focus({ workspace = " + next + " })");
			}
		}
	}
}
