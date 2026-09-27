import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "NotifTheme.js" as Theme

// swaync's volume widget: a glyph and a slider for the default sink.
//
// central_control.css:
//   .widget-volume { color: @text; padding: 4px; margin: 6px; border-radius: 8px }
//   .widget-volume > box > label { margin-right: 10px }
//
// The widget's `background: @background-sec` is dropped by GTK -- that colour is
// not defined in notifColors-waybar.css, so the declaration is invalid and swaync
// renders this widget with no background of its own. This matches it exactly;
// the panel's keyboard says where it is with a ring around one knob rather than
// by tinting the widget (see NotifTheme.js).
//
// swaync neither reads nor writes Pipewire directly: it drives wpctl. This reads
// the sink through the shell's own Pipewire connection and writes back through
// `audio.volume`, so the slider and the volume keys never disagree.
//
// Mute is the glyph in front of the slider: clicking it -- or Enter, Space or `m`
// while the panel's cursor is on this knob -- toggles the sink, and the row then
// shows the struck-through glyph with a grey fill.
//
// swaync has no brightness here -- the XF86MonBrightness keys go through
// cypher-osd -- so the second row is ours. It is driven exactly the way the OSD
// drives the backlight (`brightnessctl -c backlight`, the same class the OSD
// addresses when it is given no --device), including the same 5% step and floor,
// so the panel and the brightness keys move it identically. The slider is only
// drawn when there is a backlight to move.
Item {
	id: root

	required property var notifColors
	// Which row the panel's keyboard is on: -1 for neither, 0 for the volume
	// knob, 1 for the brightness one. The panel walks the two as separate stops,
	// so each knob is focusable on its own -- a highlight over the whole widget
	// would not say which of the two the horizontal keys are about to move.
	property int focusedRow: -1
	// The backlight is polled only while the panel is open: nothing else in the
	// shell needs it, and this is a process per poll.
	property bool poll: false

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property real level: (sink && sink.audio) ? sink.audio.volume : 0
	readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false
	// swaync's scale is 0..100 (percent), not the sink's 0..1.
	readonly property real shown: Math.min(level, 1) * 100

	// The widest advance of every glyph this section can put in a slider's icon
	// slot, handed to both rows. It keeps the two troughs on one x, and it stops
	// the volume icon from resizing when it turns into the mute one -- which
	// used to slide the scale (and its click target) left, under the pointer.
	readonly property real glyphWidth: Math.ceil(Math.max(volumeMetrics.advanceWidth,
		muteMetrics.advanceWidth, brightnessMetrics.advanceWidth))

	// The backlight, as brightnessctl reports it: 0..100 and whether there is a
	// panel to speak of at all.
	property bool hasBrightness: false
	property real brightness: 0

	// Without this the sink's audio properties are never bound.
	PwObjectTracker {
		objects: [root.sink].filter((node) => node !== null)
	}

	// The three glyphs the sliders below can show, measured in the font they are
	// drawn in. Only the advances matter here, so these are invisible.
	TextMetrics {
		id: volumeMetrics

		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize + 4
		text: Theme.volumeGlyph
	}

	TextMetrics {
		id: muteMetrics

		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize + 4
		text: Theme.volumeMutedGlyph
	}

	TextMetrics {
		id: brightnessMetrics

		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize + 4
		text: Theme.brightnessGlyph
	}

	implicitHeight: Theme.volumePadding * 2 + rows.implicitHeight

	Column {
		id: rows

		anchors.fill: parent
		anchors.margins: Theme.volumePadding
		spacing: Theme.volumeRowGap

		CenterSlider {
			width: rows.width
			notifColors: root.notifColors
			glyph: root.muted ? Theme.volumeMutedGlyph : Theme.volumeGlyph
			value: root.shown
			dim: root.muted
			focused: root.focusedRow === 0
			glyphWidth: root.glyphWidth
			glyphClickable: true
			onGlyphClicked: root.toggleMute()
			onMoved: (value) => root.setVolume(value)
		}

		CenterSlider {
			width: rows.width
			visible: root.hasBrightness
			notifColors: root.notifColors
			glyph: Theme.brightnessGlyph
			value: root.brightness
			focused: root.focusedRow === 1
			glyphWidth: root.glyphWidth
			onMoved: (value) => root.setBrightness(value)
		}
	}

	// ── the backlight ────────────────────────────────────────────────────────

	// brightnessctl's machine-readable output is one line per device:
	//   intel_backlight,backlight,100,25%,400
	// i.e. device,class,current,percent,max. One call answers both questions, and
	// an empty line (no backlight class on this machine) leaves the slider hidden.
	Process {
		id: probe

		command: ["brightnessctl", "-c", "backlight", "-m"]

		stdout: SplitParser {
			onRead: (line) => root.readBacklight(line)
		}
	}

	// Brightness writes reuse one Process: the command is set per call.
	Process {
		id: writer

		command: []
	}

	Timer {
		interval: 1500
		running: root.poll
		repeat: true

		onTriggered: {
			if (!probe.running)
				probe.running = true;
		}
	}

	onPollChanged: {
		if (root.poll && !probe.running)
			probe.running = true;
	}

	Component.onCompleted: {
		if (root.poll && !probe.running)
			probe.running = true;
	}

	function readBacklight(line) {
		var fields = line.trim().split(",");
		if (fields.length < 4) {
			root.hasBrightness = false;
			return;
		}

		var percent = parseInt(fields[3], 10);
		if (isNaN(percent)) {
			root.hasBrightness = false;
			return;
		}

		root.hasBrightness = true;
		root.brightness = percent;
	}

	// ── what the keys and the sliders call ───────────────────────────────────

	function setVolume(percent) {
		if (!root.sink || !root.sink.audio)
			return;
		root.sink.audio.volume = Math.max(0, Math.min(1, percent / 100));
	}

	function adjustVolume(delta) {
		root.setVolume(root.shown + delta);
	}

	// Mute is the one thing in this widget with no slider of its own: it is the
	// speaker glyph when clicked, and Enter/Space or `m` while the panel's cursor
	// is on the volume knob.
	function toggleMute() {
		if (!root.sink || !root.sink.audio)
			return;
		root.sink.audio.muted = !root.sink.audio.muted;
	}

	function setBrightness(percent) {
		if (!root.hasBrightness)
			return;

		var target = Math.round(Math.max(Theme.brightnessFloor, Math.min(100, percent)));
		if (target === Math.round(root.brightness))
			return;

		// Moved locally as well as through brightnessctl, so the handle follows
		// the key immediately instead of at the next poll.
		root.brightness = target;
		writer.command = ["brightnessctl", "-c", "backlight", "set", target + "%"];
		writer.running = true;
	}

	function adjustBrightness(delta) {
		root.setBrightness(root.brightness + delta);
	}
}
