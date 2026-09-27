import QtQuick
import Quickshell
import "launcher"
import "notifications"
import "osd"

// cypher-shell -- the Quickshell shell: the top bar, the launcher, the OSD and
// the notification server.
//
//   qs -c cypher-shell     run it (one bar per monitor)
//   cypher-shell start     the same, but only if it is not already up
//
// It is the whole desktop chrome: waybar's bar, walker's launcher, swaync's
// notifications and swayosd's OSD, all in one process. The stack it replaced is
// gone, so there is nothing to hand over to at start-up or back on the way out.
//
// The pieces are driven through their CLIs so the keybinds and scripts do not
// care how they are built:
//
//   cypher-menu -m menus:system/power --width 250   launcher
//   cypher-osd --output-volume raise                OSD
//   cypher-notify -t                                notifications
//   qs ipc -c cypher-shell call osd flash '{...}'
ShellRoot {
	// The bar is instantiated per screen and owns its own palette; every other
	// window here is a single one, so they are handed this instead.
	BarPalette {
		id: sharedPalette
	}

	Variants {
		model: Quickshell.screens
		delegate: Component {
			Bar {
				notifications: notifState
			}
		}
	}

	Launcher {
		palette: sharedPalette
	}

	// Notifications: one server, one popup stack and one control centre, the
	// latter two instantiated per screen and shown on the one they belong to.
	NotifState {
		id: notifState
	}

	Variants {
		model: Quickshell.screens
		delegate: Component {
			Popups {
				state: notifState
				pal: sharedPalette
			}
		}
	}

	Variants {
		model: Quickshell.screens
		delegate: Component {
			Center {
				state: notifState
				pal: sharedPalette
			}
		}
	}

	// The OSD is a single state object and a surface per screen; only the surface
	// on the monitor cypher-osd named is ever visible.
	OsdState {
		id: osdState
	}

	Variants {
		model: Quickshell.screens
		delegate: Component {
			Osd {
				state: osdState
				pal: sharedPalette
			}
		}
	}
}
