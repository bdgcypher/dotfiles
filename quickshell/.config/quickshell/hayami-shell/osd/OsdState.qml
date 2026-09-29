import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import "OsdTheme.js" as Theme

// The OSD's state, and the IPC endpoint that hayami-osd talks to.
//
// The split mirrors swayosd's: the client does the work (it is what knows how to
// talk to wpctl, brightnessctl and playerctl), and the server just draws. The
// difference is that the shell already subscribes to Pipewire, so for the volume
// bars it can read the level itself rather than being told -- `--output-volume
// raise` only has to name which bar to show, and the drawn value is the real one
// even if the client's arithmetic and wpctl's ever disagree.
//
// A caller *can* send a value, and then that wins: hayami-osd measures the level
// after changing it, which covers the case where the shell has not seen the
// Pipewire update land yet.
//
// An Item rather than a QtObject, only because PwObjectTracker and IpcHandler are
// both QObject children and a QtObject has no default property to put them in.
// It is never drawn and takes no space.
Item {
	id: root

	visible: false
	width: 0
	height: 0

	// What is on screen right now. `monitor` is resolved once, at show time, so
	// the OSD cannot jump to another screen while it is fading out.
	property bool showing: false
	property string monitor: ""
	property string kind: ""
	property string icon: ""
	property string label: ""
	property real progress: -1
	property int duration: Theme.duration

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property var source: Pipewire.defaultAudioSource

	// Without these the sink's audio properties are never bound, and the OSD
	// would draw the levels it happened to see at startup.
	PwObjectTracker {
		objects: [root.sink, root.source].filter(o => o !== null)
	}

	readonly property string focusedMonitor: {
		var m = Hyprland.focusedMonitor;
		return m ? m.name : "";
	}

	// ── drawing helpers ──────────────────────────────────────────────────────

	function levelIcon(value, muted) {
		if (muted)
			return "audio-volume-muted";
		if (value <= 0.33)
			return "audio-volume-low";
		if (value <= 0.66)
			return "audio-volume-medium";
		return "audio-volume-high";
	}

	function audioValue(source_) {
		if (!source_ || !source_.audio)
			return { value: 0, muted: false };
		return { value: source_.audio.volume, muted: source_.audio.muted };
	}

	// swayosd names its icons from the freedesktop spec; a few of those are not
	// in this icon theme, so they are mapped onto something that is. Without a
	// fallback the OSD would silently lose its icon rather than draw a wrong one.
	function resolveIcon(name) {
		if (!name)
			return "";
		if (Quickshell.iconPath(name, true) !== "")
			return name;

		var fallback = {
			"caps-lock-symbolic": "input-keyboard",
			"num-lock-symbolic": "input-keyboard",
			"scroll-lock-symbolic": "input-keyboard",
			"keyboard-brightness-medium-symbolic": "input-keyboard",
			"keyboard-brightness-high-symbolic": "input-keyboard",
			"audio-volume-overamplified": "audio-volume-high",
			"media-playlist-shuffle-symbolic": "media-playlist-shuffle",
			"media-playlist-consecutive-symbolic": "media-playlist-repeat"
		};

		var alt = fallback[name];
		return (alt && Quickshell.iconPath(alt, true) !== "") ? alt : "";
	}

	// ── show / hide ──────────────────────────────────────────────────────────

	function show(specJson) {
		var spec;
		try {
			spec = JSON.parse(specJson);
		} catch (e) {
			return;
		}
		if (!spec || !spec.kind)
			return;

		root.kind = spec.kind;
		root.duration = (typeof spec.duration === "number" && spec.duration > 0) ? spec.duration : Theme.duration;
		root.monitor = spec.monitor ? String(spec.monitor) : root.focusedMonitor;

		var out = {
			icon: spec.icon ? String(spec.icon) : "",
			label: spec.label !== undefined ? String(spec.label) : "",
			progress: (typeof spec.progress === "number" && spec.progress >= 0) ? spec.progress : -1
		};

		var level = root.audioValue(spec.kind === "input-volume" ? root.source : root.sink);
		var value = (typeof spec.value === "number") ? spec.value : level.value;
		var muted = (typeof spec.muted === "boolean") ? spec.muted : level.muted;

		if (spec.kind === "output-volume" || spec.kind === "input-volume") {
			out.icon = out.icon || root.levelIcon(value, muted);
			out.label = out.label || (Math.round(value * 100) + "%");
			out.progress = out.progress < 0 ? value : out.progress;
		} else if (spec.kind === "brightness") {
			out.icon = out.icon || "display-brightness-symbolic";
			out.label = out.label || (Math.round(value * 100) + "%");
			out.progress = out.progress < 0 ? value : out.progress;
		} else if (spec.kind === "playerctl") {
			out.icon = out.icon || "media-playback-start-symbolic";
		} else if (spec.kind === "caps-lock" || spec.kind === "num-lock" || spec.kind === "scroll-lock") {
			out.icon = out.icon || (spec.kind + "-symbolic");
			out.label = out.label || (value > 0 ? "On" : "Off");
		}

		root.icon = root.resolveIcon(out.icon);
		root.label = out.label;
		// The bar is drawn from a 0..1 fraction. Above 100% (volume-boost) the
		// caller sends a larger value; the fill is clamped where it is drawn.
		root.progress = out.progress;

		root.showing = true;
		timer.restart();
	}

	function hide() {
		timer.stop();
		root.showing = false;
	}

	Timer {
		id: timer

		// Restarted on every show, so a run of volume key presses keeps one OSD
		// on screen and only the last value is displayed -- what swayosd does.
		interval: root.duration
		onTriggered: root.showing = false
	}

	IpcHandler {
		target: "osd"

		// `flash`, not `show`: `show` is one of `qs ipc`'s own subcommands, and
		// the CLI parses a function of that name as the subcommand, leaving the
		// spec unread (it refuses the call with "argument was not expected").
		function flash(spec: string): string {
			root.show(spec);
			return root.showing ? "ok" : "ignored";
		}

		function hide(): string {
			root.hide();
			return "ok";
		}

		// What is being drawn, for probing the OSD from a script or a shell.
		function state(): string {
			return JSON.stringify({
				"showing": root.showing,
				"monitor": root.monitor,
				"kind": root.kind,
				"icon": root.icon,
				"label": root.label,
				"progress": root.progress,
				"duration": root.duration
			});
		}
	}
}
