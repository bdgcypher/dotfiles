import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// custom/voxtype -- dictation state (idle / recording / transcribing).
//
// Same source as waybar: `voxtype status --format json --follow --extended`
// streaming one JSON object per state change. The waybar module maps the object's
// "alt" field through format-icons; we do the same.
//
// style.css pulses both the recording and transcribing states with the shared
// blink animation, so both get the pulse here too -- the glyphs tell them apart.
BarItem {
	id: root

	// Not named `state`: Item already has a `state` property (QML states).
	property string dictationState: "idle"

	// custom/voxtype: "tooltip": true. voxtype's status JSON carries the text
	// waybar would show -- "Voxtype ready - hold hotkey to record", the model, the
	// device and the backend -- so it is passed straight through.
	property string statusTooltip: ""

	glyph: dictationState === "recording" ? Icons.voxtypeRecord : (dictationState === "transcribing" ? Icons.voxtypeTranscribe : "")
	pulse: dictationState === "recording" || dictationState === "transcribing"
	tooltipText: statusTooltip

	// style.css: #custom-voxtype { min-width: 12px; margin: 0 0 0 7.5px }
	// The reserved width is what stops the bar shifting as the glyph fades.
	minWidth: 12
	marginLeft: 7.5

	onClicked: Quickshell.execDetached(["voxtype-dictate"])
	onRightClicked: Quickshell.execDetached(["voxtype-configure-launcher"])

	Process {
		id: follow

		command: ["voxtype", "status", "--format", "json", "--follow", "--extended"]
		running: true

		stdout: SplitParser {
			onRead: function(line) {
				var data = null;
				try {
					data = JSON.parse(line);
				} catch (e) {
					return;
				}
				if (data && data.alt)
					root.dictationState = String(data.alt);
				root.statusTooltip = data && data.tooltip ? String(data.tooltip) : "";
			}
		}

		// The status stream ends if voxtype restarts; pick it back up.
		onRunningChanged: {
			if (!running)
				restart.start();
		}
	}

	Timer {
		id: restart
		interval: 2000

		onTriggered: follow.running = true
	}
}
