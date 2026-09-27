pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "Icons.js" as Icons
import "Theme.js" as Theme

// group/tray-expander -- status notifier icons behind a chevron.
//
// Mirrors the waybar group: a custom/expand-icon chevron (#custom-expand-icon
// 12px min-width, 18px right margin) plus a tray drawer that animates open, with
// the same 600ms transition-duration and 12px icon size. Hovering opens it, the
// same as waybar's drawer on hover -- and, like waybar's, it closes again once
// the pointer leaves the section rather than staying open.
//
// Hover is tracked for the whole section by a HoverHandler on the row itself,
// which is what makes "the section" mean the chevron, the drawer, and the gaps
// between the tray icons alike. The chevron's MouseArea cannot do that job: it
// only covers the chevron, so moving from it onto the first tray icon would read
// as leaving. The icons keep their own MouseAreas, and a handler does not take
// clicks away from them.
//
// Each icon behaves the way waybar's tray does: left click activates the item,
// right click opens the item's own DBus menu when it has one (and otherwise
// answers as a secondary activate), the wheel is forwarded to the item, and the
// item's tooltip title/description are shown on hover.
Row {
	id: root

	property var pal

	// Assigned by the HoverHandler, and forced to true while a tray item's menu
	// is up -- the pointer leaves the bar to reach the menu, and a drawer that
	// folded away under its own menu would take the anchor with it.
	property bool expanded: false

	property bool hovered: false

	// How many tray menus are open. A count rather than a flag: moving from one
	// icon's menu to another's closes the first after opening the second, and the
	// order of those two signals is not something to rely on.
	property int openMenus: 0

	// The bar hands down the screen its surface is on, so a tray menu -- a
	// full-screen overlay -- lands on the same monitor as the icon it came from.
	property var screenModel: null

	// Bumped whenever this section moves or resizes, so a menu anchored to one
	// of the icons re-reads where that icon actually is. The icons slide left as
	// the drawer opens -- the row is right-anchored, so growing the drawer pushes
	// everything in it along -- and `mapToItem` is a call rather than a property,
	// so a binding that only calls it is evaluated once, at load, and would place
	// every menu where the icons were before the drawer ever opened.
	property int geometryRevision: 0

	onXChanged: Qt.callLater(root.bumpGeometry)
	onWidthChanged: Qt.callLater(root.bumpGeometry)

	function bumpGeometry() {
		geometryRevision++
	}

	HoverHandler {
		id: hover

		onHoveredChanged: {
			root.hovered = hovered;
			if (root.openMenus === 0)
				root.expanded = hovered;
		}
	}



	// No implicitHeight here: Row is a positioner, so it computes its own from
	// the children (every one below is Theme.height). Assigning it is a
	// read-only property error at load time.

	Item {
		id: expander

		// style.css: #custom-expand-icon { margin-right: 18px } and nothing else --
		// no min-width, so the box is the glyph's advance plus that margin. The -9
		// centre offset below is what puts the glyph at the left of that margin.
		implicitWidth: chevron.implicitWidth + 18
		implicitHeight: Theme.height

		Text {
			id: chevron

			anchors.centerIn: parent
			anchors.horizontalCenterOffset: -9
			text: Icons.trayExpand
			color: root.pal ? root.pal.foreground : "#c5c4c4"
			font.family: Theme.fontFamily
			font.pixelSize: Theme.fontSize
			rotation: root.expanded ? 180 : 0

			Behavior on rotation {
				NumberAnimation {
					duration: Theme.trayDrawerDuration
					easing.type: Easing.InOutQuad
				}
			}
		}

		MouseArea {
			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor

			onClicked: root.expanded = !root.expanded
		}
	}

	Row {
		id: drawer

		spacing: Theme.traySpacing
		clip: true
		width: root.expanded ? implicitWidth : 0
		opacity: root.expanded ? 1 : 0

		Behavior on width {
			NumberAnimation {
				duration: Theme.trayDrawerDuration
				easing.type: Easing.InOutQuad
			}
		}

		Behavior on opacity {
			NumberAnimation {
				duration: Theme.trayDrawerDuration
			}
		}

		Repeater {
			model: SystemTray.items

			delegate: Item {
				id: trayItem

				required property var modelData

				implicitWidth: Theme.trayIconSize
				implicitHeight: Theme.height

				// The item's own tooltip, the pair of strings an SNI publishes for
				// exactly this purpose. waybar draws both; a blank one is dropped
				// rather than leaving a stray newline.
				readonly property string tipText: {
					var title = String(modelData && modelData.tooltipTitle ? modelData.tooltipTitle : "");
					var description = String(modelData && modelData.tooltipDescription ? modelData.tooltipDescription : "");
					if (title !== "" && description !== "")
						return title + "\n" + description;
					return title !== "" ? title : description;
				}

				IconImage {
					anchors.centerIn: parent
					implicitSize: Theme.trayIconSize
					source: trayItem.modelData.icon
				}

				MouseArea {
					id: trayMouse

					anchors.fill: parent
					acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
					cursorShape: Qt.PointingHandCursor
					hoverEnabled: true

				onClicked: function(mouse) {
					trayTip.dismiss();
					// An item that is only a menu (ItemIsMenu) has no activate to
					// speak of, so a left click opens its menu, the way GTK and
					// waybar both handle one.
					if (mouse.button === Qt.LeftButton && !(trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu)) {
						trayItem.modelData.activate();
					} else if ((mouse.button === Qt.RightButton && trayItem.modelData.hasMenu)
							|| (mouse.button === Qt.LeftButton && trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu)) {
						// What waybar does with a right click: the item's own menu,
						// rendered from the DBus menu the application publishes --
						// the same menu GTK shows in waybar, drawn in this shell's
						// chrome rather than as a platform popup.
						trayMenu.open();
					} else {
						// Middle click, and a right click on an item with no
						// menu: the SNI "secondary activate" waybar sends for
						// both.
						trayItem.modelData.secondaryActivate();
					}
				}

					onWheel: function(wheel) {
						trayItem.modelData.scroll(wheel.angleDelta.y > 0 ? 1 : -1, false);
					}
				}

				// The item's context menu. A full-screen overlay the menu draws
				// itself into -- see TrayMenu for why it cannot be an anchored
				// popup the way the tooltips are. The tray item publishes a
				// DBusMenuHandle, which is exactly what a QsMenuOpener opens.
				TrayMenu {
					id: trayMenu

					target: trayItem
					screenModel: root.screenModel
					geometryRevision: root.geometryRevision
					handle: trayItem.modelData.menu
					pal: root.pal

					onMenuOpened: {
						root.openMenus++;
						root.expanded = true;
					}

					onMenuClosed: {
						root.openMenus--;
						if (root.openMenus === 0 && !root.hovered)
							root.expanded = false;
					}
				}

				Tooltip {
					id: trayTip

					target: trayItem
					pal: root.pal
					text: trayItem.tipText
					hovered: trayMouse.containsMouse
				}


			}
		}
	}

	// style.css: #tray { margin-right: 16px }. That margin belongs to the tray
	// inside the drawer, so it only takes up room while the drawer is open -- a
	// collapsed drawer is clipped to nothing, margin included.
	Item {
		implicitWidth: root.expanded ? 16 : 0
		implicitHeight: Theme.height
	}
}
