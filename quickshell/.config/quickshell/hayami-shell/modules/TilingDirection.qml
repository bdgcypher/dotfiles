import QtQuick
import Quickshell
import Quickshell.Io
import "Theme.js" as Theme

// custom/tiling-direction -- where the next window will open.
//
// This one deliberately keeps calling scripts/tiling-direction.sh: the module
// encodes real logic (the armed preselect in /tmp/tiling-direction, whether that
// preselect was consumed, and the aspect-ratio prediction for dwindle) and the
// click target hypr-tiling-direction-toggle writes the state it reads. Keeping
// both bars on the same script means they can never disagree, and there is one
// place to fix if the logic changes.
//
// It is refreshed on signal 11, which hypr-tiling-direction-toggle sends; the
// same poke writes /tmp/hypr-bar.signal, which RefreshTrigger watches, so a toggle
// lands immediately.
//
// This module also needs the focused window: the prediction comes from the focused
// window's aspect ratio, and arming the direction is a one-shot that the next
// window to open consumes -- so the glyph has to change when focus moves even
// though nothing poked. That is what trackActiveWindow adds; the plain 1s poll this
// used to run covered the same cases but charged a probe every second forever.
BarItem {
	id: root

	property string stateText: ""
	property string stateClass: ""

	// custom/tiling-direction: "tooltip": true. The script writes the sentence
	// into the JSON's tooltip field ("Tiling direction: horizontal", "Next
	// window: new column (right)", ...).
	property string stateTooltip: ""

	// A poke that arrives while the probe is still running is queued rather than
	// dropped, so a toggle is never missed behind an in-flight read.
	property bool probeQueued: false

	glyph: stateText
	tooltipText: stateTooltip
	minWidth: 12
	dim: stateClass.indexOf("auto") >= 0 ? Theme.dimAuto : 1.0

	onClicked: Quickshell.execDetached(["hypr-tiling-direction-toggle"])

	function refresh() {
		if (probe.running)
			root.probeQueued = true;
		else
			probe.running = true;
	}

	RefreshTrigger {
		trackActiveWindow: true

		onPoked: root.refresh()
	}

	Process {
		id: probe

		// The helper script lives beside the shell's other scripts.
		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/hayami-shell/scripts/tiling-direction.sh"]

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
				root.stateText = data.text ? data.text : "";
				root.stateClass = data.class ? data.class : "";
				root.stateTooltip = data.tooltip ? data.tooltip : "";
			}
		}
	}

	Component.onCompleted: probe.running = true
}
