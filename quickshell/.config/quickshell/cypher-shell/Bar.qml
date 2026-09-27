import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "modules"
import "modules/Theme.js" as Theme

// The top bar itself.
//
// Geometry comes straight from waybar's config.jsonc ("height": 26,
// "margin": "6 12 0 12") and style.css (#waybar: 8px radius, 1.2px #444444
// border, 0.9 opacity), so swapping between the two bars moves nothing.
//
// Like waybar's "exclusive": false, the panel reserves no screen space
// (exclusiveZone 0 / ExclusionMode.Ignore): windows are free to use the strip
// behind the bar, and the rounded corners float over the desktop.
PanelWindow {
	id: bar

	required property var modelData
	screen: modelData

	// The shell's notification server, so the bell reads its state directly
	// instead of shelling out to swaync-client.
	property var notifications: null

	anchors {
		top: true
		left: true
		right: true
	}

	margins {
		top: Theme.marginTop
		left: Theme.marginSide
		right: Theme.marginSide
	}

	// The layer surface the compositor gives us comes back about one physical pixel
	// shorter than this item, and that pixel comes off the bottom edge (measured on
	// an 1.1-scaled screen: a 26px bar lands in rows 7..34.6 rather than 7..35).
	// The chrome compensates where it draws the border; this property is how much
	// it has to compensate for, expressed in physical pixels.
	readonly property var hyprMonitor: {
		var list = Hyprland.monitors.values;
		for (var i = 0; i < list.length; i++) {
			if (screen && list[i].name === screen.name)
				return list[i];
		}
		return null;
	}

	readonly property real monitorScale: {
		var scale = hyprMonitor && hyprMonitor.lastIpcObject ? hyprMonitor.lastIpcObject.scale : 0;
		return scale > 0 ? scale : 1;
	}

	implicitHeight: Theme.height
	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Top
	WlrLayershell.namespace: "quickshell:cypher-shell"
	// None: the bar never takes keyboard focus away from the focused window.
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

	// Named BarPalette, not Palette: QtQuick already exports a Palette type.
	BarPalette {
		id: pal
	}


	// The visible bar. waybar sets opacity on #waybar itself, which fades its
	// children too, so the chrome and the modules inside it share one opacity.
	//
	// The border is drawn as a rounded rect in the border colour with the
	// background inset inside it, rather than with Rectangle.border: Qt centres a
	// border pen on the item's outline, so the half of it that falls outside the
	// surface is clipped. At 1.2px that left one row of border at the top edge and
	// none at the bottom. Insetting keeps all four sides inside the surface.
	Rectangle {
		id: chrome

		anchors.fill: parent
		color: Theme.borderColor
		radius: Theme.radius
		opacity: Theme.barOpacity

		Rectangle {
			id: chromeFill

			anchors.fill: parent
			anchors.topMargin: Theme.borderWidth
			anchors.leftMargin: Theme.borderWidth
			anchors.rightMargin: Theme.borderWidth
			// One more lost pixel at the bottom than on the other three sides, so a
			// 1.2px band there ends up as wide as they are instead of a third of the
			// strength -- which is what read as the bottom border being cut off.
			anchors.bottomMargin: Theme.borderWidth + Theme.lostBottomPx / bar.monitorScale
			color: pal.background
			radius: Math.max(Theme.radius - Theme.borderWidth, 0)
		}

		Item {
			anchors.fill: parent
			anchors.leftMargin: Theme.sectionPadding
			anchors.rightMargin: Theme.sectionPadding

			// modules-left
			Row {
				id: left

				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter
				spacing: Theme.spacing

				MenuButton {
					pal: pal
				}
				Workspaces {
					pal: pal
				}
				LayoutIndicator {
					pal: pal
				}
				TilingDirection {
					pal: pal
				}
			}

			// modules-center -- centred on the bar, not on the leftover space.
			Row {
				id: center

				anchors.horizontalCenter: parent.horizontalCenter
				anchors.verticalCenter: parent.verticalCenter
				spacing: Theme.spacing

				Clock {
					pal: pal
				}
				Updates {
					pal: pal
				}
				Voxtype {
					pal: pal
				}
				RecordingIndicator {
					pal: pal
				}
			}

			// modules-right
			Row {
				id: right

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				spacing: Theme.spacing

				TrayExpander {
					pal: pal
					screenModel: bar.modelData
				}
				BluetoothIndicator {
					pal: pal
				}
				NetworkIndicator {
					pal: pal
				}
				VpnIndicator {
					pal: pal
				}
				VolumeIndicator {
					pal: pal
				}
				MemoryIndicator {
					pal: pal
				}
				CpuIndicator {
					pal: pal
				}
				NotificationIndicator {
					pal: pal
					state: bar.notifications
				}
				BatteryIndicator {
					pal: pal
				}
			}
		}
	}
}
