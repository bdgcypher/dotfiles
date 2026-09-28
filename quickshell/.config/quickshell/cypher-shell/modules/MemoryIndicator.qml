import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// memory -- used memory percentage.
//
// waybar's memory module allocates (MemTotal - MemAvailable) the same way; the
// helper script reads /proc/meminfo directly so there is no extra service to run.
BarItem {
	id: root

	property int percent: 0
	// Used memory in GiB, for the tooltip. waybar prints its own as
	// "{:.1f}GiB used".
	property real used: 0

	// waybar: "format": "\uefc5  {}% " -- icon, two spaces, value, then a trailing
	// space that Pango counts in the module's width.
	glyph: Icons.memory
	suffix: "  " + percent + "% "

	// The cluster's margin either side. waybar set no margin on #memory, which is
	// why this one used to sit tighter to its neighbours than the rest.
	marginLeft: 6
	marginRight: 6

	// memory: no tooltip-format in the config, and waybar's memory module does
	// not honour one anyway -- the string it prints is "{:.1f}GiB used".
	tooltipText: used.toFixed(1) + "GiB used"

	// The CPU module next door opens btop, which is where memory is looked at
	// anyway: the monitors are one view, so they get one click.
	onClicked: Quickshell.execDetached(["ghostty", "--class=floating.Btop", "-e", "btop"])

	Process {
		id: probe

		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/cypher-shell/scripts/mem.sh"]

		// One line, "<percent> <used GiB>".
		stdout: SplitParser {
			onRead: function(line) {
				var parts = String(line).trim().split(/\s+/);
				var value = parseInt(parts[0], 10);
				if (!isNaN(value))
					root.percent = value;
				var gib = parseFloat(parts[1]);
				if (!isNaN(gib))
					root.used = gib;
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
