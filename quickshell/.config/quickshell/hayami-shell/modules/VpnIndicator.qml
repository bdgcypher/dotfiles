import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons
import "Theme.js" as Theme

// custom/vpn -- Tailscale or OpenConnect/GlobalProtect up.
//
// The Tailscale JSON check and the openconnect lookup live in the shell's own
// scripts/vpn-status.sh, which prints the same JSON.
//
// style.css hides the disconnected state with `font-size: 0`, so the glyph is
// simply empty here.
//
// Clicking it opens the VPN popout (see VpnPanel): the two things a glyph cannot
// carry are *which* tunnel this is and how to drop it, and that is what the panel
// answers. Clicking it again closes the panel, which is what the pointer that
// opened it reaches for first.
BarItem {
	id: root

	property bool connected: false

	// custom/vpn: "tooltip": true, and vpn-status.sh writes "Tailscale
	// Connected" / "GP VPN Connected" / "No VPN" into the JSON's tooltip field.
	// Like the glyph, that is read straight out of the script so the two bars
	// cannot disagree.
	property string statusTooltip: ""

	// What the popout shows, out of that same reading: what the tunnel is
	// called, what state it is in, and the address it is reachable at. Read here
	// rather than probed again there, so the icon and the panel cannot disagree.
	property string name: ""
	property string state: ""
	property string detail: ""

	// The screen the bar is on, so the panel opens on the same monitor.
	property var screenModel: null

	// The cluster's margin either side, so it slots into the row at the same
	// spacing as its neighbours -- and a hidden module takes no room at all, so
	// they meet over it while it is down.
	marginLeft: 6
	marginRight: 6

	glyph: connected ? Icons.vpn : ""
	tooltipText: statusTooltip

	// The module's own corner inside the bar's surface, and how much of the bar
	// it takes up there, so the panel can centre on the module rather than start
	// at its leading edge -- the same sum Clock makes to place its own panel. A
	// sum of real properties rather than mapToItem(null, ...) because only a
	// property read is a dependency: a mapping would be computed once and never
	// again, so a panel opened later would come out of where the module used to
	// be.
	readonly property point vpnAnchor: Qt.point(
		(vertical ? 0 : Theme.sectionPadding) + parent.x + x,
		(vertical ? Theme.sectionPadding : 0) + parent.y + y)
	readonly property size vpnAnchorSize: Qt.size(width, height)

	onClicked: panel.open = !panel.open

	function refresh() {
		if (!probe.running)
			probe.running = true
	}

	// The panel is this module's child, not the bar's: it anchors to where the
	// indicator is, and it closes with the module that owns it when the VPN
	// module is switched off in the launcher's Bar → Toggle menu.
	VpnPanel {
		id: panel

		pal: root.pal
		edge: root.edge
		screenModel: root.screenModel
		anchor: root.vpnAnchor
		anchorSize: root.vpnAnchorSize
		connected: root.connected
		name: root.name
		state: root.state
		detail: root.detail

		// The hangup has landed: read again at once, so the glyph goes as the
		// panel does rather than up to five seconds later.
		onDisconnected: root.refresh()
	}

	Process {
		id: probe

		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/hayami-shell/scripts/vpn-status.sh"]

		// The reading is held while the panel is up: every probe blanks this
		// first, and a panel that watched that happen would shrink its box and
		// grow it back every five seconds, which reads as the thing being
		// unstable rather than as the probe working. A tunnel that really goes
		// down still clears it -- the script's answer arrives in onRead below.
		onStarted: if (!panel.open) root.connected = false

		stdout: SplitParser {
			onRead: function(line) {
				var data = null;
				try {
					data = JSON.parse(line);
				} catch (e) {
					return;
				}
				if (data && data.class)
					root.connected = (String(data.class) === "connected");
				root.statusTooltip = data && data.tooltip ? String(data.tooltip) : "";
				root.name = data && data.name ? String(data.name) : "";
				root.state = data && data.state ? String(data.state) : "";
				root.detail = data && data.detail ? String(data.detail) : "";
				// The tunnel went down under the panel. The module is about to
				// collapse and take the panel with it, so close it here while the
				// reason is still known.
				if (!root.connected)
					panel.open = false;
			}
		}
	}

	// No interval is configured for this module; the default is 5s.
	Timer {
		interval: 5000
		running: true
		repeat: true

		onTriggered: root.refresh()
	}
}
