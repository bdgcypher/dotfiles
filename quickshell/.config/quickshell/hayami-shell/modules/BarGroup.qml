import QtQuick
import "Theme.js" as Theme

// One of the bar's three module groups: the left, centre and right sections of a
// horizontal bar, and the top, middle and bottom sections of a vertical one.
//
// A Grid rather than a Row, because the same group has to run along whichever
// axis the bar is on: `rows: 1` lays the modules out in a row (what a Row did)
// and `columns: 1` stacks them (what a Column would do), with no second
// declaration of the module list and no rotation of the modules themselves --
// a sideways glyph is not what "the bar moved to the left edge" should mean.
//
// The modules inside are unchanged by this: they are handed the bar's edge
// through BarItem and lay themselves out from it.
Grid {
	id: root

	property bool vertical: false

	rows: vertical ? -1 : 1
	columns: vertical ? 1 : -1

	// The 8px between modules was measured between modules sharing one row.
	// Stacked, each module already carries its own leading and trailing margins,
	// so the gap only has to keep neighbours apart; see Theme.verticalSpacing.
	spacing: vertical ? Theme.verticalSpacing : Theme.spacing
}
