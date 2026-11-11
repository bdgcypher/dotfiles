import QtQuick
import Quickshell
import Quickshell.Io

// What dictation is doing, and how loud the microphone is.
//
// Two long-lived streams that more than one surface needs: the bar's module and
// the window glow are two views of one dictation, so each running its own
// `voxtype status --follow` would be two clocks for them to disagree over. The
// module used to own that process; it now reads this instead.
//
// The microphone is read by cava because Quickshell's Pipewire service exposes a
// source's *volume*, not its samples -- there is no signal level to bind to.
// cava is already on this machine for the visualiser, opens the default source
// when it starts and releases it when it exits, so it runs only while the
// microphone is actually open.
//
// An Item rather than a QtObject only because Process needs a QObject parent
// with a default property to sit in. It is never drawn.
Item {
	id: root

	visible: false
	width: 0
	height: 0

	// ── the daemon ───────────────────────────────────────────────────────────

	// Not named `state`: Item already has a `state` property (QML states). The
	// value is the daemon's own: idle, recording or transcribing.
	property string dictationState: "idle"
	property string tooltip: ""

	readonly property bool recording: dictationState === "recording"
	readonly property bool transcribing: dictationState === "transcribing"

	// Whether the microphone is open -- the one thing every consumer gates on.
	// `listening` rather than `active`, which PanelWindow already uses for the
	// window's own focus state.
	readonly property bool listening: recording || transcribing

	Process {
		id: follow

		command: ["voxtype", "status", "--format", "json", "--follow", "--extended"]
		running: true

		stdout: SplitParser {
			onRead: function(line) {
				var data = null
				try {
					data = JSON.parse(line)
				} catch (e) {
					return
				}
				if (data && data.alt)
					root.dictationState = String(data.alt)
				root.tooltip = data && data.tooltip ? String(data.tooltip) : ""
			}
		}

		// The stream ends if voxtype restarts; pick it back up.
		onRunningChanged: {
			if (!running)
				restart.start()
		}
	}

	Timer {
		id: restart
		interval: 2000
		onTriggered: follow.running = true
	}

	// ── the microphone ───────────────────────────────────────────────────────

	// Three bands, each 0..1, rather than cava's 32 bars: a band is all the glow
	// needs -- each of its four edges reads one scalar, and 32 bars around the
	// perimeter would be an equaliser pretending to be a border.
	//
	// The gain is fixed on purpose. cava already normalises with autosens, but
	// speech still sits well under music; dividing by 36 (38 for the edge
	// bands) rather than by the 100-point range is what makes the ring move
	// when you talk instead of only when you shout. Math.min keeps a loud word
	// from pushing the shader past its own clamp. The three divisors were
	// measured against a speech-shaped signal through this exact config: the
	// bands peaked at 28.4 (level), 24.1 (bass) and 26.1 (treble), so none of
	// them saturates before full volume, while ordinary syllables still reach
	// roughly half of full travel.
	property real level: 0
	property real bass: 0
	property real treble: 0

	Process {
		id: wave

		command: ["cava", "-p", Quickshell.env("HOME")
			+ "/.config/quickshell/hayami-shell/data/dictation-cava.conf"]

		stdout: SplitParser {
			onRead: function(line) { root.analyse(line) }
		}

		// cava can die under us -- the device disappears, the config is bad --
		// and it is cheap to bring back, so it is restarted for as long as the
		// daemon says it is recording.
		onRunningChanged: {
			if (!running && root.recording)
				waveRestart.start()
		}
	}

	Timer {
		id: waveRestart
		interval: 1000
		onTriggered: if (!wave.running && root.recording) wave.running = true
	}

	// The daemon's state is the analyser's switch. On the way out the bands are
	// zeroed too, so the glow's own smoothing has somewhere to fall while it
	// fades -- otherwise the last syllable would hang in the glow for as long as
	// transcription takes.
	onRecordingChanged: {
		if (recording) {
			waveRestart.stop()
			wave.running = true
		} else {
			waveRestart.stop()
			wave.running = false
			level = 0
			bass = 0
			treble = 0
		}
	}

	// cava's ascii output is one frame per line: 32 values 0..100 separated by
	// `;`, with a trailing delimiter that yields an empty last field.
	//
	// A malformed or empty frame is ignored rather than treated as silence: a
	// dropped frame from a busy device would otherwise flick the whole ring dark
	// for a frame.
	function analyse(line) {
		var fields = String(line).split(";")
		if (fields.length < 8)
			return

		var sum = 0
		var count = 0
		var low = 0
		var lowCount = 0
		var high = 0
		var highCount = 0

		for (var i = 0; i < fields.length; i++) {
			if (fields[i] === "")
				continue
			var value = Number(fields[i])
			if (!isFinite(value))
				continue
			sum += value
			count++
			// cava draws bass on the left and treble on the right.
			if (i < fields.length / 3) {
				low += value
				lowCount++
			} else if (i >= fields.length * 2 / 3) {
				high += value
				highCount++
			}
		}

		if (count === 0)
			return

		level = Math.min(1, (sum / count) / 36)
		bass = lowCount > 0 ? Math.min(1, (low / lowCount) / 38) : 0
		treble = highCount > 0 ? Math.min(1, (high / highCount) / 38) : 0
	}
}
