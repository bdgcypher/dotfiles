import QtQuick
import Quickshell
import "Theme.js" as Theme

// clock -- the date and the time in one reading, and the way into the calendar.
//
// waybar had the two as a click-toggle:
//          format     "{:L%A %I:%M %p}"  -> "Tuesday 03:45 PM"
//          format-alt "{:L%B %d, %Y}"    -> "September 23, 2026"
// They are one line now -- "04:29 PM · September 27th, 2026" -- so there is
// nothing left to toggle.
//
// The click opens the calendar panel instead (see CalendarPanel): asking "what
// is the date?" is what clicking a clock means, and the month, the week numbers
// and the year's progress all want to be read in one place rather than in a
// terminal window. Root-clicking it again closes the panel, which is what the
// pointer that opened it reaches for first. The panel is the shell's own and is
// bound to BarState, so SUPER+SHIFT+C reaches the same month from the keyboard.
BarItem {
	id: root

	// BarState, passed down by Bar.qml: the calendar's three preferences are
	// saved beside the bar's own edge and hidden modules.
	property var state: null
	// The screen the bar is on, so the panel opens on the same monitor.
	property var screenModel: null
	// Whether this is the bar on the monitor with the focus. The calendar's open
	// flag is one per shell and the panel is one per bar, so the panel asks
	// whether it is the one that may answer it -- the same gate the agent
	// popout uses, for the same reason.
	property bool focused: false

	// Assembled from formats rather than written as one strftime string: the day's
	// ordinal suffix is not something any format specifier produces, so Qt gives
	// the time, Qt gives the month and the day, this inserts the "th", and Qt
	// gives the rest. A quoted literal separator would also have to be trusted to
	// Qt's format parser, which the concatenation simply sidesteps.
	//
	// The time leads and the date follows, both in the formats waybar used.
	readonly property string clockText: Qt.formatDateTime(clock.date, "hh:mm AP")
		+ " · " + Qt.formatDateTime(clock.date, "MMMM d")
		+ ordinalSuffix + Qt.formatDateTime(clock.date, ", yyyy")

	// "1st", "2nd", "3rd", "4th", right up to "31st" -- except that the teens
	// take "th" the whole way through: 11th, 12th and 13th, never 11st, 12nd and
	// 13rd. The last two digits are all that decides it, which is why 111 would
	// be "th" as well.
	readonly property string ordinalSuffix: {
		var day = clock.date.getDate()
		if (day % 100 >= 11 && day % 100 <= 13)
			return "th"
		if (day % 10 === 1)
			return "st"
		if (day % 10 === 2)
			return "nd"
		if (day % 10 === 3)
			return "rd"
		return "th"
	}

	glyph: clockText

	// The clock is the one module a vertical bar cannot re-arrange: 29 characters
	// is 174px of text in a 26px well, and there is no stacked form of it that is
	// not either clipped or a column of single characters. So it is turned a
	// quarter instead and reads *along* the bar, where 174px of length is
	// nothing. It is the whole module there -- no glyph above it and no value
	// under it -- so both of the stack's own lines stay empty.
	verticalGlyph: ""
	verticalValue: ""
	verticalSide: clockText	// style.css: #clock { margin-left: 5px }
	marginLeft: 5

	// The clock's own corner inside the bar's surface, adding up the offsets the
	// bar's layout puts between the two -- the module's place in its group, the
	// group's in the row, and the row's own inset -- the same sum TrayExpander
	// makes to place its panel. A sum of real properties rather than
	// mapToItem(null, ...) because only a property read is a dependency: a
	// mapping would be computed once and never again, so a panel opened later
	// would come out of where the clock used to be.
	readonly property point calendarAnchor: Qt.point(
		(vertical ? 0 : Theme.sectionPadding) + parent.x + x,
		(vertical ? Theme.sectionPadding : 0) + parent.y + y)

	// How much of the bar the module takes up, so the panel can centre on it
	// rather than hang off its leading edge -- the same sum, one axis over.
	readonly property size calendarAnchorSize: Qt.size(width, height)

	onClicked: {
		// The click and the keybind are two ways into BarState's one flag; neither
		// writes the panel's own `open`, which is a binding of that flag.
		if (state)
			state.toggleCalendarPanel()
	}

	// The panel is this module's child, not the bar's: it anchors to where the
	// clock is, and it closes with the module that owns it when the clock is
	// switched off in the launcher's Bar → Toggle menu.
	CalendarPanel {
		id: panel

		pal: root.pal
		edge: root.edge
		screenModel: root.screenModel
		state: root.state
		focused: root.focused
		anchor: root.calendarAnchor
		anchorSize: root.calendarAnchorSize
	}

	SystemClock {
		id: clock

		precision: SystemClock.Minutes
	}
}
