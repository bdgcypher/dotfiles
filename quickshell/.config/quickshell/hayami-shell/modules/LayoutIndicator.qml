import QtQuick
import Quickshell
import Quickshell.Io

// custom/workspace-layout -- the active workspace's tiling layout.
//
// This runs scripts/workspace-layout.sh rather than reading
// Hyprland.focusedWorkspace.lastIpcObject.tiledLayout directly, which is what the
// module does and for a reason: Hyprland publishes no event when a
// workspace's layout changes, so that value goes stale the moment you toggle the
// layout and nothing ever invalidates it.
//
// Taking the glyph from the same script also means the bar cannot
// disagree about it, and there is one place to change the logic.
//
// Quickshell has no signal mechanism, so
// RefreshTrigger re-runs the probe when the layout changes (via
// /tmp/hypr-bar.signal, written by hypr-toggle-layout), when focus moves to
// another workspace, and on a slow poll as a fallback.
BarItem {
	id: root

	property string stateText: ""

	// custom/workspace-layout: "tooltip": true, and the script puts "Layout:
	// dwindle"/"Layout: scrolling"/"No active workspace" in the JSON's tooltip
	// field -- which is where the glyph script reads it from too.
	property string stateTooltip: ""

	// A poke that arrives while the probe is still running is queued rather than
	// dropped, so a toggle is never missed behind an in-flight read.
	property bool probeQueued: false

	glyph: stateText
	tooltipText: stateTooltip
	minWidth: 12
	marginLeft: 7.5
	marginRight: 7.5

	onClicked: Quickshell.execDetached(["hypr-toggle-layout"])

	function refresh() {
		if (probe.running)
			root.probeQueued = true;
		else
			probe.running = true;
	}

	RefreshTrigger {
		onPoked: root.refresh()
	}

	Process {
		id: probe

		// The helper script lives beside the shell's other scripts.
		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/hayami-shell/scripts/workspace-layout.sh"]

		onRunningChanged: {
			if (!probe.running && root.probeQueued) {
				root.probeQueued = false;
				probe.running = true;
			}
		}

		stdout: SplitParser {
			onRead: function(line) {
				var data = null;
				try {
					data = JSON.parse(line);
				} catch (e) {
					return;
				}
				root.stateText = data && data.text ? String(data.text) : ""
				root.stateTooltip = data && data.tooltip ? String(data.tooltip) : "";
			}
		}
	}

	Component.onCompleted: probe.running = true
}
