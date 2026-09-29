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

	// style.css: #pulseaudio { min-width: 12px; margin: 0 7.5px }. The min-width
	// carries over; the margin is the cluster's -- see BluetoothIndicator.
	minWidth: 12
	marginLeft: 6
	marginRight: 6

	// All three go through volume-boost, which is what the volume keys use --
	// and that is the point of sharing it rather than calling wpctl here: one
	// step size, one 125% ceiling to stop at, and one OSD pill for the change,
	// whichever way the volume was moved. Calling wpctl straight from the bar
	// left the wheel and the keys disagreeing at the top of the range, and mute
	// from the bar said nothing on screen.
	onClicked: Quickshell.execDetached(["volume-boost", "mute"])
	onRightClicked: Quickshell.execDetached(["ghostty", "--class=floating.Wiremix", "-e", "wiremix"])
	onScrolled: function(delta) {
		Quickshell.execDetached(["volume-boost", delta > 0 ? "up" : "down"]);
	}

	// Without this the sink's volume/muted properties are not bound, so the bar
	// would sit on its initial value.
	PwObjectTracker {
		objects: root.sink !== null ? [root.sink] : []
	}
}
