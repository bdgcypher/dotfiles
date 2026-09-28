import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "Icons.js" as Icons

// battery -- UPower display device.
//
// Reproduces the waybar module's three visible states:
//   discharging  "{icon} {capacity}%"
//   charging     "{icon} {capacity}%"
//   full         󰂅
// plus its 10%-band icon ladder for both the charging and discharging sets, and
// its habit of hiding the module entirely when there is no battery.
//
// One deliberate departure: waybar's own config flips the icon to the far side
// while charging (format-discharging is "{icon} {capacity}%" but
// format-charging is "{capacity}% {icon}"). The icon leads in every state here,
// so the module reads the same whether or not the charger is plugged in.
//
// waybar's on-click was "menu power", which does not exist on this machine; the
// real power menu is the launcher entry the SUPER+ESCAPE bind opens.
BarItem {
	id: root

	readonly property var device: UPower.displayDevice
	readonly property bool present: device !== null && device.isPresent
	// Quickshell passes UPower's percentage through as a 0-1 fraction, not 0-100:
	// reading it raw and rounding made a 63% battery render as "1%".
	readonly property int capacity: present ? Math.round(device.percentage * 100) : 0
	readonly property bool charging: present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
	readonly property bool full: present && device.state === UPowerDeviceState.FullyCharged

	// UPower reports the rate in watts, signed: positive while the pack is taking
	// charge. waybar's tooltip ignores the sign and prints the arrow instead, so
	// only the magnitude is used here.
	readonly property real power: present ? Math.abs(device.changeRate) : 0

	readonly property string bandIcon: bandFor(charging ? Icons.batteryCharging : Icons.batteryDischarging)
	// Charging and discharging have their own icon ladders (a bolt in the first,
	// plain fill in the second); `full` is a single fixed glyph.
	readonly property string icon: full ? Icons.batteryFull : bandIcon

	// No explicit `visible` here: an absent battery means an empty glyph, and
	// BarItem already collapses empty modules the way waybar does.
	// BarItem renders `glyph + suffix`, so icon-then-percentage is the order in
	// both the charging and discharging states.
	glyph: !present ? "" : icon
	suffix: (!present || full) ? "" : " " + capacity + "%"

	// style.css: #battery { min-width: 12px; margin: 0 7.5px }. The min-width
	// carries over; the margin is the cluster's -- see BluetoothIndicator.
	minWidth: 12
	marginLeft: 6
	marginRight: 6

	// battery: "tooltip-format-discharging": "{power:>1.0f}W↓ {capacity}%" and
	// "tooltip-format-charging": "{power:>1.0f}W↑ {capacity}%". A full pack is
	// still on the charger, so it takes the up arrow rather than falling through
	// to a third wording waybar does not define.
	tooltipText: !present ? "" : (power.toFixed(1) + "W" + ((charging || full) ? "↑ " : "↓ ") + capacity + "%")

	onClicked: Quickshell.execDetached(["cypher-menu", "-m", "menus:system/power", "--width", "250"])
	// Right click is the power *profile* rather than the power menu the left
	// click already opens: the two answer different questions, and the profile
	// is the one with nowhere else to live on the bar. Same command as the
	// launcher's System → Setup → Power Profile entry.
	onRightClicked: Quickshell.execDetached(["ghostty", "--class=floating.Power", "-e", "power-profile"])

	function bandFor(ladder) {
		var band = Math.floor(capacity / 10);
		if (band > 9)
			band = 9;
		if (band < 0)
			band = 0;
		return ladder[band];
	}
}
