import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// custom/update -- pending pacman/AUR updates.
//
// Source: yay -Qu. One run at startup,
// then hourly, plus an immediate re-check when `piu` finishes an update run and
// writes the signal file below. The glyph stays hidden while the count is zero,
// matching the empty text printed in the "uptodate" state.
BarItem {
	id: root

	// -1 while the first check is still running.
	property int count: -1

	// The pending package names, in the order yay printed them. The
	// updates helper caches the same list and puts the first fifteen of them in
	// the tooltip, so the names are kept here rather than only counted.
	property var pending: []

	// Nothing at all until the count is known: the "checking" branch only
	// runs when its cache file is missing, so in practice it shows an empty module
	// on start-up rather than a spinner-ish icon. Matching that keeps the centre
	// section from jumping every time the bar starts.
	glyph: count > 0 ? Icons.updates + " " + count : ""
	fontSize: 10
	minWidth: 12
	marginLeft: 7.5
	marginRight: 7.5

	// custom/update: "tooltip": true, and the helper's own
	// "%s update(s):\n%s" -- the count, then up to fifteen package names with an
	// ellipsis when there are more.
	tooltipText: {
		if (count <= 0)
			return "";
		var shown = pending.slice(0, 15).join(" ");
		if (count > 15)
			shown += "...";
		return count + " update(s):\n" + shown;
	}

	onClicked: Quickshell.execDetached(["ghostty", "--class=floating.Pacman", "-e", "piu"])

	Process {
		id: check

		command: ["yay", "-Qu"]

		property int lines: 0

		onStarted: {
			lines = 0;
			names = [];
		}
		// Process has no exit signal in the 0.3 API surface, so the finished
		// state is read off `running` going false after a start.
		onRunningChanged: {
			if (!running && lines > 0) {
				root.pending = names.slice();
				root.count = lines;
				lines = 0;
			} else if (!running) {
				root.pending = [];
				root.count = 0;
			}
		}

		// The helper's own `awk '{print $1}'` over `yay -Qu`: the package name is
		// the first word of the line.
		property var names: []

		stdout: SplitParser {
			onRead: function(line) {
				if (line.length > 0) {
					check.lines++;
					check.names.push(String(line).split(/\s+/)[0]);
				}
			}
		}
	}

	Timer {
		interval: 3600000
		running: true
		repeat: true

		onTriggered: {
			if (!check.running)
				check.running = true;
		}
	}

	// piu writes this file when an update run finishes. Without it the count
	// would keep showing the packages that were just installed, for up to an
	// hour, because nothing the bar can observe changes.
	FileView {
		path: "/tmp/hayami-updates.signal"
		watchChanges: true
		printErrors: false

		onFileChanged: {
			if (!check.running)
				check.running = true;
		}
	}

	Component.onCompleted: check.running = true
}
