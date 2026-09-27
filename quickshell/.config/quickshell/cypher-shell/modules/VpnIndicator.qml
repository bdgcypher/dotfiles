import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// custom/vpn -- Tailscale or OpenConnect/GlobalProtect up.
//
// The Tailscale JSON check and the openconnect lookup live in the shell's own
// scripts/vpn-status.sh, which prints the same JSON the waybar module consumed.
//
// style.css hides the disconnected state with `font-size: 0`, so the glyph is
// simply empty here.
BarItem {
	id: root

	property bool connected: false

	// custom/vpn: "tooltip": true, and vpn-status.sh writes "Tailscale
	// Connected" / "GP VPN Connected" / "No VPN" into the JSON's tooltip field.
	// Like the glyph, that is read straight out of the script so the two bars
	// cannot disagree.
	property string statusTooltip: ""

	glyph: connected ? Icons.vpn : ""
	tooltipText: statusTooltip

	Process {
		id: probe

		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/cypher-shell/scripts/vpn-status.sh"]

		onStarted: root.connected = false

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
			}
		}
	}

	// style.css has no interval for this module; waybar's default is 5s.
	Timer {
		interval: 5000
		running: true
		repeat: true

		onTriggered: {
			if (!probe.running)
				probe.running = true;
		}
	}
}
