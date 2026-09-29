import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// cpu -- CPU usage percentage.
//
// The helper script diffs two /proc/stat reads, which is what waybar's cpu module
// effectively shows; an average-since-boot figure would barely move on a 5s
// refresh. Left click opens btop in a floating ghostty.
BarItem {
	id: root

	property int percent: 0

	glyph: Icons.cpu
	suffix: " " + percent + "%"

	// cpu: no tooltip-format in the config, and waybar's cpu module ignores one
	// anyway; its hardcoded tooltip is the usage alone.
	tooltipText: percent + "%"

	// style.css: #cpu { min-width: 12px; margin: 0 7.5px }. The min-width carries
	// over; the margin is the cluster's -- see BluetoothIndicator.
	minWidth: 12
	marginLeft: 6
	marginRight: 6

	onClicked: Quickshell.execDetached(["ghostty", "--class=floating.Btop", "-e", "btop"])

	Process {
		id: probe

		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/hayami-shell/scripts/cpu.sh"]

		stdout: SplitParser {
			onRead: function(line) {
				var value = parseInt(line, 10);
				if (!isNaN(value))
					root.percent = value;
			}
		}
	}

	// waybar: "interval": 5
	Timer {
		interval: 5000
		running: true
		repeat: true

		onTriggered: {
			if (!probe.running)
				probe.running = true;
		}
	}

	Component.onCompleted: probe.running = true
}
