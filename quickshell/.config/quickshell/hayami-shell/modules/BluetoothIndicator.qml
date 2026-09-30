import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "Icons.js" as Icons

// bluetooth -- adapter state plus connected device count.
//
// The three format states map to: powered on with
// something connected, adapter off or missing, and powered on with nothing
// connected. Left click opens bluetui in a floating ghostty.
BarItem {
	id: root

	property var adapter: Bluetooth.defaultAdapter
	property int connectedCount: 0

	readonly property bool ready: adapter !== null && adapter.enabled

	// Every indicator carries the same margin either side, so the steps between
	// them all come out the same -- 6px on each side measures 24px of clear space
	// between the icons. A 17px margin-right is not carried
	// over: it made up for a wider icon box there, and here it only pushed this
	// icon away from the wifi one.
	marginLeft: 6
	marginRight: 6

	// Every other state gets an empty format string -- "" powered on with
	// nothing connected, "" disabled, "" no controller -- so the module only ever
	// shows a glyph while something is actually connected to it.
	glyph: ready && connectedCount > 0 ? Icons.btConnected : ""

	// bluetooth: "tooltip-format": "Devices connected: {num_connections}"
	tooltipText: "Devices connected: " + connectedCount

	// Bluetooth.devices is a model, so its per-device `connected` flag is not a
	// bindable QML property here; re-read it on a slow timer instead.
	Timer {
		interval: 3000
		running: true
		repeat: true
		onTriggered: root.refresh()
	}

	Component.onCompleted: refresh()

	function refresh() {
		root.adapter = Bluetooth.defaultAdapter;

		var count = 0;
		var devices = Bluetooth.devices.values;
		for (var i = 0; i < devices.length; i++) {
			if (devices[i].connected)
				count++;
		}
		root.connectedCount = count;
	}

	onClicked: Quickshell.execDetached(["ghostty", "--class=floating.Bluetui", "-e", "bluetui"])
}
