import QtQuick
import Quickshell

// clock -- current time, with waybar's format / format-alt toggle.
//
// waybar:  format     "{:L%A %I:%M %p}"  -> "Tuesday 03:45 PM"
//          format-alt "{:L%B %d, %Y}"    -> "September 23, 2026"
//          on-click-right opens aion in a floating ghostty
BarItem {
	id: root

	property bool showDate: false

	glyph: showDate
		? Qt.formatDateTime(clock.date, "MMMM d, yyyy")
		: Qt.formatDateTime(clock.date, "dddd hh:mm AP")

	// style.css: #clock { margin-left: 5px }
	marginLeft: 5

	onClicked: root.showDate = !root.showDate
	onRightClicked: Quickshell.execDetached(["ghostty", "--class=floating.Calendar", "-e", "aion"])

	SystemClock {
		id: clock
		precision: SystemClock.Minutes
	}
}
