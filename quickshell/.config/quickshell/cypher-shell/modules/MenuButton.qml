import QtQuick
import Quickshell
import "Icons.js" as Icons

// custom/menu -- opens the launcher, exactly like the waybar module it replaces.
//
// Goes through cypher-menu rather than calling the launcher in-process, so the
// bar button and the keybind are one entry point with one set of flags.
BarItem {
	glyph: Icons.menu
	minWidth: 12
	marginLeft: 7.5
	marginRight: 7.5

	// custom/menu: "tooltip-format": "Menu"
	tooltipText: "Menu"

	onClicked: Quickshell.execDetached(["cypher-menu", "--width", "250"])
}
