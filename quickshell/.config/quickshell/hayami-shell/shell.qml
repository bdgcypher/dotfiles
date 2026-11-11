import QtQuick
import Quickshell
import "launcher"
import "modules"
import "notifications"
import "osd"

// hayami-shell -- the Quickshell shell: the top bar, the launcher, the OSD and
// the notification server.
//
//   qs -c hayami-shell     run it (one bar per monitor)
//   hayami-shell start     the same, but only if it is not already up
//
// It is the whole desktop chrome: the bar, the launcher, the notification
// centre and the OSD, all in one process. Nothing external to hand over to at
// start-up or back on the way out.
//
// The pieces are driven through their CLIs so the keybinds and scripts do not
// care how they are built:
//
//   hayami-menu -m menus:system/power --width 250   launcher
//   hayami-osd --output-volume raise                OSD
//   hayami-notify -t                                notifications
//   qs ipc -c hayami-shell call osd flash '{...}'
ShellRoot {
	// The bar is instantiated per screen and owns its own palette; every other
	// window here is a single one, so they are handed this instead.
	BarPalette {
		id: sharedPalette
	}

	// Where the bar is and what it shows. One object for the whole shell, because
	// the bar is the same bar on every monitor: an edge or a switched-off module
	// applies to all of them, and the drag that moves it is a change to that one
	// setting.
	BarState {
		id: barState
	}

	// What dictation is doing and how loud the microphone is. One reading for
	// the whole shell: the bar's module and the glow are two views of it, and
	// the microphone analyser behind it is one process rather than one per
	// monitor.
	DictationState {
		id: dictationState
	}

	// The one thing about the tray that is not per-monitor: a request to pop its
	// panel out, which the launcher's System -> Setup -> System Tray entry makes.
	// See TrayState for why it cannot live on the panel itself.
	TrayState {
		id: trayState
	}

	Variants {
		model: Quickshell.screens
		delegate: Component {
			Bar {
				state: barState
				tray: trayState
				notifications: notifState
				dictation: dictationState
			}
		}
	}

	// The ghost of the bar, drawn on the monitor the pointer is on while a drag is
	// live. One per screen, like the bar itself, and only the dragged one draws.
	Variants {
		model: Quickshell.screens
		delegate: Component {
			BarDragPreview {
				state: barState
				pal: sharedPalette
			}
		}
	}

	Launcher {
		id: launcher
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
	// on the monitor hayami-osd named is ever visible.
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

	// The dictation glow. One surface per monitor, like the bar, because a layer
	// surface cannot be moved between outputs; each instance works out whether
	// the focused window is on its monitor and stays unmapped if it is not.
	//
	// The panels are passed in so the ring can stand down while one of them is
	// over the window it would be drawn around -- see DictationGlow.qml.
	Variants {
		model: Quickshell.screens
		delegate: Component {
			DictationGlow {
				pal: sharedPalette
				dictation: dictationState
				bar: barState
				notifications: notifState
				launcherOpen: launcher.open
			}
		}
	}
}
