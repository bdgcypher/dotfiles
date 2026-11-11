import QtQuick
import Quickshell
import "Icons.js" as Icons

// custom/voxtype -- dictation state (idle / recording / transcribing).
//
// The reading is the shell's, not the module's: DictationState.qml owns the one
// `voxtype status --format json --follow --extended` stream and the glow reads
// the same one. That is why this module no longer runs the process itself -- a
// second stream would be a second clock for the glyph and the glow to disagree
// over, and the glow would never know the glyph had gone quiet.
//
// style.css pulses both the recording and transcribing states with the shared
// blink animation, so both get the pulse here too -- the glyphs tell them apart.
BarItem {
	id: root

	// The shell's shared dictation reading; see DictationState.qml.
	property var dictation: null

	// Not named `state`: Item already has a `state` property (QML states).
	readonly property string dictationState: dictation ? dictation.dictationState : "idle"

	// custom/voxtype: "tooltip": true. voxtype's status JSON carries the text
	// show -- "Voxtype ready - hold hotkey to record", the model, the
	// device and the backend -- so it is passed straight through.
	readonly property string statusTooltip: dictation ? dictation.tooltip : ""

	glyph: dictationState === "recording" ? Icons.voxtypeRecord : (dictationState === "transcribing" ? Icons.voxtypeTranscribe : "")
	pulse: dictationState === "recording" || dictationState === "transcribing"
	tooltipText: statusTooltip

	// style.css: #custom-voxtype { min-width: 12px; margin: 0 0 0 7.5px }
	// The reserved width is what stops the bar shifting as the glyph fades.
	minWidth: 12
	marginLeft: 7.5

	onClicked: Quickshell.execDetached(["voxtype-dictate"])
	onRightClicked: Quickshell.execDetached(["voxtype-configure-launcher"])
}
