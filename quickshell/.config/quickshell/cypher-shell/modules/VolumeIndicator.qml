import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "Icons.js" as Icons

// pulseaudio -- default sink volume.
//
// waybar's format is "{icon}  {volume}% " and its format-muted is just the muted
// glyph, so both are reproduced here. Left click toggles mute, right click opens
// wiremix, and the scroll step is 5% like waybar's scroll-step.
BarItem {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property bool muted: (sink !== null && sink.audio !== null) ? sink.audio.muted : false
	readonly property real volume: (sink !== null && sink.audio !== null) ? sink.audio.volume : 0

	readonly property string volumeIcon: muted ? Icons.volMuted : (volume <= 0.5 ? Icons.volLow : Icons.volHigh)

	glyph: muted ? volumeIcon + " " : volumeIcon + "  "
	suffix: muted ? "" : Math.round(volume * 100) + "% "

	// pulseaudio: "tooltip-format": "Volume: {volume}%" -- the sink's own level,
	// mute or not, which is what waybar reports there.
	tooltipText: "Volume: " + Math.round(volume * 100) + "%"

	// style.css: #pulseaudio { min-width: 12px; margin: 0 7.5px }
	minWidth: 12
	marginLeft: 7.5
	marginRight: 7.5

	onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
	onRightClicked: Quickshell.execDetached(["ghostty", "--class=floating.Wiremix", "-e", "wiremix"])
	onScrolled: function(delta) {
		Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", delta > 0 ? "5%+" : "5%-"]);
	}

	// Without this the sink's volume/muted properties are not bound, so the bar
	// would sit on its initial value.
	PwObjectTracker {
		objects: root.sink !== null ? [root.sink] : []
	}
}
