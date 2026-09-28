pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import "Icons.js" as Icons
import "Theme.js" as Theme

// group/tray-expander -- status notifier icons behind a chevron.
//
// waybar's group put the icons in a drawer that opened along the bar, growing the
// section until it held the whole row. Here the chevron is a module like any
// other -- it never changes size, so nothing beside it moves -- and the icons
// live in a panel of their own, off the side of the bar, in a grid. The bar's row
// stays still; the tray reads as a flyout.
//
// The chevron points the way the panel comes out -- away from the bar on every
// edge (down from a top bar, out to the right of a left one) -- and flips a half
// turn when the panel is open, so it reads as the thing that opened.
//
// ── why the panel is a surface of its own ────────────────────────────────────
//
// The shell's tooltips are popups anchored to the item they describe, and the
// tray icons still need theirs, plus their right-click menus. A popup is placed
// against its anchor item by the compositor, which needs that item to be in a
// surface that can parent one -- a layer surface, as the bar is. Rendering the
// panel as a popup anchored to the chevron would therefore make every icon's
// tooltip a popup whose parent is a popup, one grab away from the refusal in
// TrayMenu's own notes. A content-sized layer surface has none of that problem:
// the icons are in a surface exactly like the bar, so their tooltips and menus
// work the way they always have, and the panel itself is placed by its anchors.
//
// ── open and shut ────────────────────────────────────────────────────────────
//
// Hovering the chevron opens the panel, the way hovering waybar's chevron opened
// the drawer. The pointer then has to cross a few pixels of desktop to reach the
// panel, so the close is delayed rather than immediate (Theme.trayPanelCloseDelay)
// -- and while a tray item's context menu is up the panel is held open outright,
// since that menu is anchored to an icon inside it.
Item {
	id: root

	property var pal
	property string edge: "top"

	// Whether the bar is showing the tray at all. TrayExpander is not a BarItem,
	// so it carries its own copy of the switch the modules get from BarItem -- the
	// key is still BarState's, in Bar.qml, and this is only what it lands on.
	property bool moduleShown: true

	// The bar hands down the screen its surface is on, so the panel lands on the
	// same monitor as the bar it belongs to.
	property var screenModel: null

	// The tray's shared request, which is the launcher's way in -- see TrayState.
	// Copying the signal is not enough for the property name: it is the tray's
	// own request, not this item's state, and every bar is handed the same one.
	property var trayState: null

	// The cluster's margin on both sides, the same as every indicator beside it
	// (see BluetoothIndicator). waybar's #custom-expand-icon kept 18px after
	// itself to clear the drawer's first icon; there is no drawer to clear now, so
	// the chevron takes the row's own spacing instead.
	property real marginLeft: 6
	property real marginRight: 6

	readonly property bool vertical: Theme.isVertical(edge)

	// The accent every list in this shell marks focus with: @color3 when the
	// palette has it, otherwise the accent -- the same pair TrayMenu and the
	// launcher use.
	readonly property color highlight: pal && pal.colors && pal.colors.length > 3
		? pal.colors[3] : (pal && pal.accent ? pal.accent : "#CEA56A")

	// The box the chevron occupies, following BarItem's convention: the glyph plus
	// its margins, the glyph inset by them, so a step along the row measures the
	// same here as between two indicators next door.
	implicitWidth: vertical ? Theme.verticalWell : chevron.implicitWidth + marginLeft + marginRight
	implicitHeight: vertical ? chevron.implicitHeight + marginLeft + marginRight : Theme.height
	visible: moduleShown

	// The next step after the bar, where the panel starts.
	readonly property real pastBar: Theme.marginTop + Theme.thicknessFor(edge) + Theme.trayPanelGap

	readonly property real screenW: screenModel ? screenModel.width : 0
	readonly property real screenH: screenModel ? screenModel.height : 0

	// The chevron's own corner inside the bar's surface, adding up the offsets the
	// bar's layout puts between the two: the chevron's place in the module, the
	// module's in its group, and the group's in the row Bar.qml insets by
	// sectionPadding on the axis the modules run along.
	//
	// A sum of real properties rather than chevron.mapToItem(null, ...) because
	// only a property read is a dependency: a mapping would be computed once and
	// then never again, so the panel would not follow the chevron when a module
	// beside it appeared or went away and the group grew.
	readonly property point chevronInBar: Qt.point(
		(vertical ? 0 : Theme.sectionPadding) + parent.x + x + chevron.x,
		(vertical ? Theme.sectionPadding : 0) + parent.y + y + chevron.y)

	// Where the bar's strip starts on the screen: the margin it keeps to the edge
	// it is on, and the margin at its ends -- the same pair, in the same order,
	// that Bar.qml places its strip with on every edge. The bar's *surface* is the
	// whole screen now, so this is a screen coordinate, which is the space the
	// panel's own margins below are measured in.
	readonly property real barOriginX: edge === "right"
		? screenW - Theme.thicknessFor(edge) - Theme.marginTop
		: (edge === "left" ? Theme.marginTop : Theme.marginSide)
	readonly property real barOriginY: edge === "bottom"
		? screenH - Theme.thicknessFor(edge) - Theme.marginTop
		: (edge === "top" ? Theme.marginTop : Theme.marginSide)

	// Where the panel's leading edge goes along the bar: at the chevron, so the
	// panel comes out of the caret that opened it instead of out of the bar's far
	// corner, and slid back inside the screen when the panel is too long to sit
	// there (a tray of many icons, or a chevron near an end of the bar).
	readonly property real followX: Math.max(Theme.marginSide,
		Math.min(barOriginX + chevronInBar.x, screenW - panel.implicitWidth - Theme.marginSide))
	readonly property real followY: Math.max(Theme.marginSide,
		Math.min(barOriginY + chevronInBar.y, screenH - panel.implicitHeight - Theme.marginSide))

	// ... and read once, as the panel opens. The panel takes the place the caret
	// was in when it opened and keeps it for as long as it is up: a layer
	// surface's anchors and margins are read at map time and the protocol has no
	// way to move a mapped one, so chasing the caret live would mean dropping the
	// surface and putting it back, which is a blink -- and takes any tooltip the
	// pointer is resting on down with it. The caret only drifts for reasons that
	// have nothing to do with the tray (a volume going from 99% to 100%, a VPN
	// indicator coming up), and a panel that jumped a few pixels for those would
	// be the worse trade. See takePlace().
	property real panelX: 0
	property real panelY: 0

	function takePlace() {
		panelX = followX
		panelY = followY
	}

	property bool expanded: false

	// Where the pointer is: on the chevron, or on one of the icons in the panel.
	property bool hovered: false
	property bool panelHovered: false

	// The cell the pointer is on, -1 when it is on nothing. Kept on the root rather
	// than read off a cell's own MouseArea because a cell is rebuilt whenever the
	// grid is (a tray item coming or going rewrites the model), and a fresh
	// MouseArea starts with containsMouse false while the pointer is still resting
	// on it -- which would retire that icon's tooltip out from under the pointer.
	// The cell index survives the rebuild; see the MouseArea in the grid.
	property int hoveredIcon: -1

	// How many tray menus are open. A count rather than a flag: moving from one
	// icon's menu to another's closes the first after opening the second, and the
	// order of those two signals is not something to rely on.
	property int openMenus: 0

	// ── opened with the keyboard ─────────────────────────────────────────────
	//
	// Hovering the caret opens the panel for the pointer, and that is unchanged.
	// This is the other way in, taken by the launcher's System -> Setup -> System
	// Tray entry: the panel comes up on its own and takes the keyboard, and one
	// icon is marked as the one the arrows are on. It has to be shut deliberately
	// then -- escape, or a click on the caret -- because the pointer is not part of
	// this at all, and a panel that folded away the moment the mouse wandered off
	// would be no use from the keyboard.
	property bool keyboard: false

	// The icon the keyboard is on, as a flat index into the grid.
	property int focusedIcon: 0

	readonly property int iconCount: itemRepeater.count

	// The bars all watch the one request; only the bar whose screen it names
	// answers it. Bound rather than connected so the pairing is a property read:
	// TrayState sets the monitor before it bumps the counter, so by the time this
	// re-evaluates it can see both.
	readonly property int trayRequest: trayState ? trayState.requests : 0
	onTrayRequestChanged: if (trayState && screenModel && trayState.monitor === screenModel.name) openWithKeyboard()

	function openWithKeyboard() {
		keyboard = true
		focusedIcon = 0
		closeDelay.stop()
		// The pointer had no say in this one, so the place is taken here rather
		// than in onWantedChanged.
		if (!expanded)
			takePlace()
		expanded = true
	}

	function closeWithKeyboard() {
		keyboard = false
		expanded = false
	}

	// ── taking the keyboard back ─────────────────────────────────────────────
	//
	// A context menu is a surface of its own, and the compositor gives the
	// keyboard to whichever layer surface asked for it last. It does not give it
	// back when that surface goes away -- the panel is still mapped, so nothing
	// new happens for the compositor to react to, and the keys would fall through
	// to the window behind. The panel therefore asks again, the only way the
	// protocol offers: the keyboard-interactivity property is a *request*, so it
	// is dropped and remade rather than left standing.
	property bool reclaiming: false

	readonly property bool wantsKeyboard: keyboard && expanded && !reclaiming

	function reclaimKeyboard() {
		reclaiming = true
		reclaim.restart()
	}

	Timer {
		id: reclaim

		// Long enough for the menu's surface to be gone: asking while it is still
		// mapped would hand the keyboard straight back to it.
		interval: 80

		onTriggered: root.reclaiming = false
	}

	// One step of the grid, stopping at the edges rather than wrapping: the icons
	// are a small fixed field, and a step that teleported to the far side of it
	// would be easy to lose your place in. Up and down move a whole row, which is
	// the panel's own wrapping (Theme.trayPanelColumns).
	function moveIconFocus(dx, dy) {
		var next = focusedIcon + dx + dy * Theme.trayPanelColumns
		if (next < 0 || next >= iconCount)
			return
		focusedIcon = next
	}

	// What enter and space do: the focused icon's menu, which is where every tray
	// item on this machine keeps its "open". An item with no menu at all has
	// nothing to show, so it gets its click instead.
	function openFocusedMenu() {
		var icon = itemRepeater.itemAt(focusedIcon)
		if (icon)
			icon.openContextMenu()
	}

	// A tray item can come and go while the panel is up.
	onIconCountChanged: if (focusedIcon >= iconCount) focusedIcon = Math.max(0, iconCount - 1)

	// A shut panel is not holding the keyboard, whoever shut it. The caret is
	// clickable, so hovering the panel open and then clicking the caret is a way
	// out of keyboard mode as well as escape -- and leaving the flag set would
	// keep the panel "wanted", which is what stops the next hover from opening it
	// again.
	onExpandedChanged: {
		if (expanded)
			return
		// Shut: whatever cell the pointer was on is moot, and leaving it set
		// would put that icon's tooltip up unasked the next time the panel opens.
		hoveredIcon = -1
		keyboard = false
	}

	// The panel is wanted while the pointer is on either half of it, held while a
	// context menu is up, and held outright while the keyboard owns it.
	readonly property bool wanted: keyboard || hovered || panelHovered || openMenus > 0

	onWantedChanged: {
		if (!wanted) {
			closeDelay.restart();
			return;
		}
		closeDelay.stop();
		// The one moment the caret's place is taken: opening. A panel that is
		// already up keeps the place it has, so nothing here moves it once the
		// surface is mapped.
		if (!expanded)
			takePlace();
		expanded = true;
	}

	// The crossing between the chevron and the panel: the pointer is on neither
	// for a moment, and the panel would fold away under it if that moment counted.
	Timer {
		id: closeDelay

		interval: Theme.trayPanelCloseDelay

		onTriggered: {
			if (!root.wanted)
				root.expanded = false;
		}
	}

	// Bumped whenever the panel resizes or the bar changes edge, so a menu
	// anchored to one of the icons re-reads where that icon is. The icons do not
	// move as the panel opens -- the panel is not in the bar -- but they do move
	// when an application adds or removes a tray item, which rewrites the grid.
	property int geometryRevision: 0

	// The bar changing edge is the one thing that would have to move the panel
	// while it is up: the anchors themselves change, and a mapped layer surface
	// cannot be re-anchored. The panel belongs to the edge it came out of, so it
	// shuts with the edge and opens at the caret again the next time it is asked
	// for -- which is also the only moment the place can be trusted, since the bar
	// is still laying its modules out again for the new edge for a frame or two.
	onEdgeChanged: {
		Qt.callLater(root.bumpGeometry)
		if (expanded)
			expanded = false
	}

	function bumpGeometry() {
		geometryRevision++;
	}

	// The caret, pointing the way the panel will come out: down from a top bar, up
	// from a bottom one, and out towards the desktop from a vertical one.
	//
	// The glyph is a left angle (Icons.trayExpand, nf-fa-angle_left) and QML turns
	// it clockwise, so its tip reads left at 0, down at +90, right at 180 and up at
	// -90 -- which is where each of these comes from. Verified against the rendered
	// bar: at rotation 0 the tip is on the left, and a top bar's caret points down.
	readonly property real shutRotation: edge === "top" ? -90
		: edge === "bottom" ? 90
		: edge === "left" ? 180
		: 0

	Text {
		id: chevron

		anchors.centerIn: parent
		anchors.horizontalCenterOffset: root.vertical ? 0 : (root.marginLeft - root.marginRight) / 2
		anchors.verticalCenterOffset: root.vertical ? (root.marginLeft - root.marginRight) / 2 : 0
		text: Icons.trayExpand
		color: root.pal ? root.pal.foreground : "#c5c4c4"
		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize
		rotation: root.expanded ? root.shutRotation + 180 : root.shutRotation

		Behavior on rotation {
			NumberAnimation {
				duration: Theme.trayPanelFlipDuration
				easing.type: Easing.InOutQuad
			}
		}
	}

	MouseArea {
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor

		// Hover drives the panel, so a click is only ever the explicit toggle: on
		// a chevron the pointer is already over, it shuts a panel that hover has
		// opened, and it stays shut until the pointer leaves and comes back.
		onClicked: root.expanded = !root.expanded
		onHoveredChanged: root.hovered = containsMouse
	}

	// ── the panel ────────────────────────────────────────────────────────────
	//
	// A content-sized layer surface in the corner the tray sits in: the bar's end
	// on the near edge, just past the bar itself on the far one. Pinned to the
	// corner rather than tracking the chevron, so it does not shift as the modules
	// beside the chevron change width.
	PanelWindow {
		id: panel

		screen: root.screenModel

		// Nothing to show with an empty tray, so the panel does not come up at all
		// rather than opening as an empty box.
		visible: root.expanded && itemRepeater.count > 0

		// Two axes, two rules: just past the bar on the axis the bar's own
		// thickness occupies, and at the chevron on the axis its length runs along.
		// The near axis is a plain margin; the along one is root.panelX/panelY, the
		// caret's screen position as it was when the panel opened, clamped to keep
		// the surface whole. `anchors.top` on a vertical bar is therefore the along
		// axis there, not the near one -- on a left bar the panel comes out of the
		// bar's right side and is read down the screen from the caret.
		anchors.top: root.edge === "top" || root.vertical
		anchors.bottom: root.edge === "bottom"
		anchors.left: root.edge === "left" || !root.vertical
		anchors.right: root.edge === "right"

		margins.top: root.edge === "top" ? root.pastBar : (root.vertical ? root.panelY : 0)
		margins.bottom: root.edge === "bottom" ? root.pastBar : 0
		margins.left: root.edge === "left" ? root.pastBar : (!root.vertical ? root.panelX : 0)
		margins.right: root.edge === "right" ? root.pastBar : 0

		// Sized to its contents: the grid, the panel's own padding, and its border.
		implicitWidth: grid.implicitWidth + (Theme.trayPanelPad + Theme.trayPanelBorderWidth) * 2
		implicitHeight: grid.implicitHeight + (Theme.trayPanelPad + Theme.trayPanelBorderWidth) * 2

		exclusiveZone: 0
		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Top
		WlrLayershell.namespace: "quickshell:tray-panel"
		// None while the pointer is what opened it: taking the keyboard for a
		// flyout that a hover brings up would interrupt whatever is being typed
		// into the window behind it. Exclusive when the launcher sent us here,
		// because then the keyboard is the thing driving the icons.
		WlrLayershell.keyboardFocus: root.wantsKeyboard
			? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		// Where this surface's top-left corner is on the screen, worked out from
		// the anchors and margins above. TrayMenu places itself from an icon's
		// rectangle inside *this* surface, and its own arithmetic only knows the
		// bar's margins, so it is handed this instead.
		readonly property point origin: {
			var x = 0;
			var y = 0;
			if (root.edge === "right")
				x = root.screenW - root.pastBar - implicitWidth;
			else if (root.edge === "left")
				x = root.pastBar;
			else
				x = root.panelX;
			if (root.edge === "bottom")
				y = root.screenH - root.pastBar - implicitHeight;
			else if (root.vertical)
				y = root.panelY;
			else
				y = root.pastBar;
			return Qt.point(x, y);
		}

		onImplicitWidthChanged: Qt.callLater(root.bumpGeometry)
		onImplicitHeightChanged: Qt.callLater(root.bumpGeometry)

		// Whether the pointer is anywhere on the panel, icons and padding alike.
		// A HoverHandler on the panel rather than the icons: the icons' own
		// MouseAreas cover only themselves, so the padding between them would read
		// as leaving.
		HoverHandler {
			id: panelHover

			onHoveredChanged: root.panelHovered = hovered
		}

		// The box, drawn the way the bar, the tooltips and the OSD draw theirs: a
		// rounded rect in the border colour with the background inset inside it,
		// because Qt centres a border pen on the item's outline and clips the
		// outer half.
		Rectangle {
			anchors.fill: parent
			color: Theme.borderColor
			radius: Theme.trayPanelRadius

			Rectangle {
				anchors.fill: parent
				anchors.margins: Theme.trayPanelBorderWidth
				color: panel.pal ? panel.pal.background : "#171513"
				radius: Math.max(Theme.trayPanelRadius - Theme.trayPanelBorderWidth, 0)
			}
		}

		// The icons, in a grid that wraps. Four across fits a tray of this
		// machine's size in a panel narrower than a tooltip; a longer tray grows
		// downwards rather than off the screen.
		Grid {
			id: grid

			x: Theme.trayPanelBorderWidth + Theme.trayPanelPad
			y: Theme.trayPanelBorderWidth + Theme.trayPanelPad
			columns: Theme.trayPanelColumns
			spacing: Theme.trayPanelSpacing

			Repeater {
				id: itemRepeater

				model: SystemTray.items

				delegate: Item {
					id: trayItem

					required property var modelData
					// The cell's place in the grid, which is what the keyboard's index
					// and the focus ring are expressed in.
					required property int index


					// The square the icon is centred in: the click target, and what
					// the grid's spacing is measured between.
					implicitWidth: Theme.trayPanelCell
					implicitHeight: Theme.trayPanelCell

					// The item's own tooltip, the pair of strings an SNI publishes
					// for exactly this purpose. waybar draws both; a blank one is
					// dropped rather than leaving a stray newline.
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

					// Where the keyboard is. An outline around the whole cell rather
					// than the list menus' bar down the left edge: the icons are a
					// field, not a list, and the bar would land in the gap between two
					// of them. Drawn over the icon so it reads on artwork that fills
					// its square.
					Rectangle {
						anchors.fill: parent
						anchors.margins: Theme.trayPanelFocusInset
						radius: Theme.trayPanelFocusRadius
						color: "transparent"
						border.width: Theme.trayPanelFocusBorderWidth
						border.color: root.highlight
						visible: root.keyboard && root.focusedIcon === trayItem.index
					}

					MouseArea {
						id: trayMouse

						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
						cursorShape: Qt.PointingHandCursor
						hoverEnabled: true

						onClicked: function(mouse) {
							trayTip.dismiss();
							// An item that is only a menu (ItemIsMenu) has no
							// activate to speak of, so a left click opens its
							// menu, the way GTK and waybar both handle one.
							if (mouse.button === Qt.LeftButton && !(trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu)) {
								trayItem.modelData.activate();
							} else if ((mouse.button === Qt.RightButton && trayItem.modelData.hasMenu)
									|| (mouse.button === Qt.LeftButton && trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu)) {
								// What waybar does with a right click: the item's
								// own menu, rendered from the DBus menu the
								// application publishes -- the same menu GTK shows
								// in waybar, drawn in this shell's chrome rather
								// than as a platform popup.
								trayMenu.open();
							} else {
								// Middle click, and a right click on an item with
								// no menu: the SNI "secondary activate" waybar
								// sends for both.
								trayItem.modelData.secondaryActivate();
							}
						}

					onWheel: function(wheel) {
						trayItem.modelData.scroll(wheel.angleDelta.y > 0 ? 1 : -1, false);
					}

					// Which cell the pointer is on, kept on the root rather than read
					// off containsMouse by whoever needs it: the tooltip wants to
					// follow the pointer across a panel that may be rebuilt under it
					// (a tray item coming or going rewrites the grid), and a cell's
					// own MouseArea is the wrong place to remember that from.
					onContainsMouseChanged: {
						if (containsMouse)
							root.hoveredIcon = trayItem.index
						else if (root.hoveredIcon === trayItem.index)
							root.hoveredIcon = -1
					}
				}

					// What the keyboard's enter and space do. The same thing a right
					// click does, so the two ways into an item's menu go through one
					// line: the icon's own menu when it has one, and its click when
					// it does not, since a menu-less item has nothing else to give.
					function openContextMenu() {
						if (trayItem.modelData.hasMenu)
							trayMenu.open()
						else
							trayItem.modelData.activate()
					}

					// The item's context menu. A full-screen overlay the menu
					// draws itself into -- see TrayMenu for why it cannot be an
					// anchored popup the way the tooltips are. The tray item
					// publishes a DBusMenuHandle, which is exactly what a
					// QsMenuOpener opens. The panel hands down its own origin,
					// since this icon is not in the bar.
					TrayMenu {
						id: trayMenu

						target: trayItem
						screenModel: root.screenModel
						edge: root.edge
						geometryRevision: root.geometryRevision
						surfaceOrigin: panel.origin
						handle: trayItem.modelData.menu
						pal: root.pal

					onMenuOpened: {
						// Every way into a menu comes through here -- the right
						// click, the ItemIsMenu left click, and enter/space from
						// the keyboard -- so this is where the icon's tooltip is
						// retired. The mouse's own dismiss() in onClicked covers
						// only its own path, and left the tooltip sitting over the
						// menu when the menu came from the keyboard.
						trayTip.dismiss();
						root.openMenus++;
						root.expanded = true;
					}

						onMenuClosed: {
							root.openMenus--;
							if (root.openMenus === 0 && !root.wanted)
								root.expanded = false;
							// Back to the icons, since the keyboard was the menu's while
							// it was up.
							if (root.openMenus === 0 && root.keyboard)
								root.reclaimKeyboard();
						}

						// An entry was activated, so the application has the screen now:
						// the menu is already shutting (TrayMenu.activateEntry), and the
						// panel shuts with it. Left up, it would sit over the application
						// that was just opened, and in keyboard mode it would be holding
						// the session's keyboard too -- the panel would have to be
						// dismissed by hand before the application could be used.
						onEntryActivated: {
							// The pointer is over neither half of the tray by now, but
							// the panel's hover can be left standing when a surface maps
							// over it, and a stale true there is what keeps the panel
							// "wanted" -- which would put it straight back up. A real
							// hover event re-sets both the moment the pointer moves.
							root.hovered = false
							root.panelHovered = false
							root.keyboard = false
							root.expanded = false
						}
					}

					Tooltip {
						id: trayTip

						target: trayItem
						pal: root.pal
						edge: root.edge
						text: trayItem.tipText
						// The pointer's tooltip, or the keyboard's place in the grid: the
						// focused icon says what it is without being pointed at. The
						// pointer's half is root.hoveredIcon -- see the MouseArea above for
						// why it is not simply containsMouse.
						hovered: root.hoveredIcon === trayItem.index || (root.keyboard && root.focusedIcon === trayItem.index)
					}
				}
			}
		}

		// The keyboard, while the panel was opened from the launcher. It has to sit
		// on an item that can hold focus -- a window's own content item cannot --
		// and holding it is what makes the surface's exclusive keyboard focus mean
		// anything: the compositor delivers the keys to this window, and this is the
		// item inside it that they land on.
		FocusScope {
			id: panelKeys

			anchors.fill: parent
			focus: root.keyboard && root.expanded

			// Escape is the way out, since the pointer is not part of this. An open
			// context menu has the keyboard itself, so its own escape closes that
			// first and this one is reached only once the grid is what has focus.
			Keys.onEscapePressed: root.closeWithKeyboard()

			Keys.onPressed: function(event) {
				switch (event.key) {
				// The arrows and hjkl are the same four moves, as in every other
				// list in this shell.
				case Qt.Key_Left:
				case Qt.Key_H:
					root.moveIconFocus(-1, 0)
					event.accepted = true
					break
				case Qt.Key_Right:
				case Qt.Key_L:
					root.moveIconFocus(1, 0)
					event.accepted = true
					break
				case Qt.Key_Up:
				case Qt.Key_K:
					root.moveIconFocus(0, -1)
					event.accepted = true
					break
				case Qt.Key_Down:
				case Qt.Key_J:
					root.moveIconFocus(0, 1)
					event.accepted = true
					break
				case Qt.Key_Return:
				case Qt.Key_Enter:
				case Qt.Key_KP_Enter:
				case Qt.Key_Space:
					root.openFocusedMenu()
					event.accepted = true
					break
				}
			}
		}
	}
}
