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
Row {
	id: root

	property var pal

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
		}
	}
}
