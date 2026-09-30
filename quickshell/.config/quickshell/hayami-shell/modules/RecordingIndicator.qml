import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// custom/screen-recording-indicator -- pulsing dot while wf-recorder is running.
//
// This is watched by running a one-shot command that tests for
// /tmp/wf_recording_active and is re-run on signal 8. Nothing observes the file
// itself, so a single long-lived watcher process reports it instead: no polling
// forks, and the state is always current.
//
// style.css gives the recording state 0 4px padding / 3px 5px margin and the
// stopped state nothing at all, which is what the margin switches below do.
BarItem {
	id: root

	property bool recording: false

	glyph: recording ? Icons.recordDot : ""
	pulse: recording
	// custom/screen-recording-indicator: the helper's JSON carries this tooltip
	// only while the file it tests for exists, so there is nothing to show once
	// recording has stopped -- and the module has collapsed by then anyway.
	tooltipText: recording ? "Recording in progress... (Click icon or press SUPER + R to stop)" : ""
	marginLeft: recording ? 5 : 0
	marginRight: recording ? 5 : 0
	// style.css: .recording { padding: 0 4px; margin: 3px 5px }
	paddingLeft: recording ? 4 : 0
	paddingRight: recording ? 4 : 0

	onClicked: Quickshell.execDetached(["screen-record"])

	Process {
		id: watcher

		command: ["sh", "-c", "while true; do if [ -f /tmp/wf_recording_active ]; then echo on; else echo off; fi; sleep 1; done"]
		running: true

		stdout: SplitParser {
			onRead: function(line) {
				root.recording = (line.trim() === "on");
			}
		}

		onRunningChanged: {
			if (!running)
				restart.start();
		}
	}

	Timer {
		id: restart
		interval: 2000

		onTriggered: watcher.running = true
	}
}
