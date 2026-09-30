import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "Icons.js" as Icons

// network -- wifi signal ladder, ethernet, or disconnected.
//
// The icon is picked by the connected device type and, for wifi, by the
// signal strength band; ethernet always shows 󰀂 and a missing connection shows
// 󰤮. Left click opens gazelle in a floating ghostty.
//
// The tooltip reads -- "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}"
// for wifi, the two arrows alone for ethernet, "Disconnected" when there is no
// link -- with the frequency and the two rates coming from scripts/net-tooltip.sh
// (see that file for why they are not read here).
BarItem {
	id: root

	property string icon: Icons.netOff
	property string ssid: ""

	// The interface the tooltip's rate probe is pointed at, or "" with no link.
	property string iface: ""
	// False when neither a wired nor a wireless device is connected.
	property bool linked: false
	// True while the link is wifi, which is what decides whether the tooltip
	// carries the network name and its frequency.
	property bool wirelessLink: false

	property string frequency: ""
	property real downRate: 0
	property real upRate: 0

	// Same margin either side as the rest of the cluster -- see the note in
	// BluetoothIndicator. A 13px margin-right was the inset that
	// left this icon floating furthest from its neighbours.
	marginLeft: 6
	marginRight: 6
	glyph: icon

	// network: the three tooltip-format variants, in the config's own wording.
	tooltipText: {
		if (!linked)
			return "Disconnected";
		var head = "";
		if (wirelessLink) {
			head = ssid;
			if (frequency !== "")
				head += " (" + frequency + " GHz)";
			head += "\n";
		}
		return head + "⇣" + rateText(downRate) + "  ⇡" + rateText(upRate);
	}

	// The byte rate is scaled to the largest unit that fits, with one
	// decimal, so 1500 is "1.5KiB/s" and 0 is "0.0B/s".
	function rateText(bytes) {
		var units = ["B", "KiB", "MiB", "GiB"];
		var value = bytes;
		var at = 0;
		while (value >= 1024 && at < units.length - 1) {
			value /= 1024;
			at++;
		}
		return value.toFixed(1) + units[at] + "/s";
	}

	onClicked: Quickshell.execDetached(["ghostty", "--class=floating.Gazelle", "-e", "gazelle"])

	// Networking.devices is a model whose devices update their own state, so poll
	// rather than depend on change notification this API surface does not expose.
	Timer {
		interval: 3000
		running: true
		repeat: true
		onTriggered: root.refresh()
	}

	Component.onCompleted: refresh()

	// The rate probe runs on the same 3s beat as the in-process refresh, which is
	// also what the module's own interval did.
	Process {
		id: rateProbe

		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/hayami-shell/scripts/net-tooltip.sh", root.iface]

		stdout: SplitParser {
			onRead: function(line) {
				var parts = String(line).split("\t");
				root.frequency = parts.length > 0 ? parts[0] : "";
				root.downRate = parts.length > 1 ? (parseFloat(parts[1]) || 0) : 0;
				root.upRate = parts.length > 2 ? (parseFloat(parts[2]) || 0) : 0;
			}
		}
	}

	// {essid} is the network's own name, not the interface's, so the
	// connected network is what the tooltip names.
	function networkName(device) {
		var networks = device.networks.values;
		for (var i = 0; i < networks.length; i++) {
			if (networks[i].connected)
				return networks[i].name;
		}
		return device.name;
	}

	function signalIcon(device) {
		var strength = 0;
		var networks = device.networks.values;
		for (var i = 0; i < networks.length; i++) {
			if (networks[i].connected)
				strength = networks[i].signalStrength;
		}

		var band = strength <= 0.20 ? 0 : strength <= 0.40 ? 1 : strength <= 0.60 ? 2 : strength <= 0.80 ? 3 : 4;
		return Icons.wifi[band];
	}

	function refresh() {
		var devices = Networking.devices.values;
		var wired = null;
		var wireless = null;

		for (var i = 0; i < devices.length; i++) {
			var device = devices[i];
			if (!device.connected)
				continue;
			if (device.type === DeviceType.Wired)
				wired = device;
			else if (device.type === DeviceType.Wifi)
				wireless = device;
		}

		if (wired !== null) {
			root.icon = Icons.ethernet;
			root.ssid = wired.name;
			root.iface = wired.name;
			root.linked = true;
			root.wirelessLink = false;
		} else if (wireless !== null) {
			root.icon = root.signalIcon(wireless);
			root.ssid = root.networkName(wireless);
			root.iface = wireless.name;
			root.linked = true;
			root.wirelessLink = true;
		} else {
			root.icon = Icons.netOff;
			root.ssid = "";
			root.iface = "";
			root.linked = false;
			root.wirelessLink = false;
			root.frequency = "";
			root.downRate = 0;
			root.upRate = 0;
		}

		if (root.iface !== "" && !rateProbe.running)
			rateProbe.running = true;
	}
}
