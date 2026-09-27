pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Icons.js" as Icons
import "Theme.js" as Theme

// A tray item's context menu, drawn by the shell.
//
// Quickshell ships QsMenuAnchor for this, but the anchor renders a *platform*
// QMenu, which needs Quickshell started in QApplication mode -- a switch for the
// whole shell. This draws the same menu itself instead, from the same DBusMenu
// the application publishes, in the shell's own chrome: the rounded box the
// tooltips and the OSD use, the bar's font, and the accent hover marker every
// other list in this shell marks focus with.
//
// What a tray menu has to carry, taken from the two real ones on this machine
// (Zoom's is the deep one: ten top-level entries, a seventeen-entry language
// submenu, and a checkmark on the current language):
//
//   * separators, invisible entries with type=separator
//   * entries the application marks invisible, which DBusMenuItem drops for us
//   * entries that are disabled
//   * icons, when an entry has one
//   * checkboxes and radio buttons, with their state
//   * submenus
//   * mnemonics: DBusMenu labels carry a leading underscore ("_Open Zoom
//     Workplace"), which is a keyboard cue, not part of the label
//
// Activating an entry is the application's, not ours: sendTriggered() is the
// DBusMenu "clicked" event, the same one the platform menu sends.
//
// ── why this is a full-screen surface and not an anchored popup ──────────────
//
// The obvious shape is a PopupWindow anchored to the tray icon, the way the
// tooltips are. A menu also has to *hold* the session the way a menu does,
// though: take the keyboard so the arrows and escape reach it, and take the next
// click wherever it lands so clicking away closes it. A popup that does that
// needs a grab, and a grab needs an xdg_popup -- which the compositor will not
// give a popup whose parent is a layer surface. The grab is refused outright:
//
//   Failed to create grabbing popup. Ensure popup ... has a transientParent set
//     and that parent window has received input.
//   Cannot attach popup ... as the popup is not an xdg_popup.
//
// So the menu is a full-screen transparent layer surface instead, on the top
// layer, exactly the way the notification centre works. Everything outside the
// drawn box is a click target that dismisses, and the surface holds the keyboard
// while it is open -- which is what lets the compositor deliver the arrows and
// escape. The box is placed from the icon's own rectangle, measured in the bar's
// surface and offset by the bar's margins.
//
// ── one window, a column per level ───────────────────────────────────────────
//
// A submenu is not a window of its own here. A QML component cannot instantiate
// itself -- Quickshell rejects that outright -- so a menu that opened submenus as
// nested windows would have to be a chain of files with a hard depth, each one
// spawning the next. Instead the whole cascade is drawn in this one surface, a
// column per open level, laid out side by side: the same thing a GTK menu shows,
// and it keeps the submenu's columns from being pushed around by the screen edge
// independently of the menu they belong to.
//
// The columns are fed by a fixed set of QsMenuOpener objects, one per level (see
// level0..level4), each pointed at the entry the level above opened. That is what
// the cascade depth cap in Theme.js is for.
//
// The tree is a live view: an application that rebuilds its layout while the menu
// is up (Zoom does, for the language list) makes this menu follow along.
PanelWindow {
	id: menu

	// ── interface ────────────────────────────────────────────────────────────

	// The item the menu hangs off: the tray icon. The menu is positioned from
	// this item's rectangle in the bar, so the bar's surface offset is the only
	// arithmetic involved.
	required property Item target

	// The screen the bar (and so the icon) is on, so the full-screen surface
	// lands on the same monitor.
	required property var screenModel

	// A counter the bar bumps whenever the tray section moves, so the position
	// below is re-read. See TrayExpander.geometryRevision for why a binding cannot
	// simply call mapToItem and expect to be re-evaluated.
	required property int geometryRevision

	// The menu to draw: the DBusMenuHandle the tray item publishes. A handle
	// *is* what a QsMenuOpener opens -- its children are the top-level entries --
	// so no unwrapping is needed here.
	required property var handle

	// The bar's theme colours, handed down so the menu re-tints with the
	// wallpaper like everything else.
	required property var pal

	// Whether the menu is up. Set by open()/dismiss().
	property bool shown: false

	// The open cascade: one entry per level, each the index of the row that
	// opened the column to its right. Empty means just the menu itself.
	property var path: []

	// The row the keyboard is on, in the deepest column. -1 for none.
	property int focused: -1

	// ── colours ──────────────────────────────────────────────────────────────

	readonly property color background: pal && pal.background ? pal.background : "#171513"
	readonly property color foreground: pal && pal.foreground ? pal.foreground : "#c5c4c4"
	readonly property color muted: pal && pal.muted ? pal.muted : "#686766"
	// The highlight the launcher and the other menus use: @color3 when the
	// palette has it, otherwise the accent.
	readonly property color highlight: pal && pal.colors && pal.colors.length > 3
		? pal.colors[3] : (pal && pal.accent ? pal.accent : "#CEA56A")

	// ── labels ───────────────────────────────────────────────────────────────

	// A DBusMenu label with its mnemonic marker removed. The underscore is a
	// keyboard cue for a platform menu bar, and this menu is driven by the
	// pointer and the arrows; a doubled underscore is a literal one.
	function stripLabel(text) {
		if (!text)
			return ""
		return String(text)
			.replace(/__/g, "\u0000")
			.replace(/_/g, "")
			.replace(/\u0000/g, "_")
	}

	// ── the menu being drawn ─────────────────────────────────────────────────
	//
	// One opener per possible column. An opener holds the entries of the level
	// it is pointed at, and each is pointed at the entry the level above opened
	// -- so level 1's opener is fed by level 0's entries at path[0], and so on.
	// The last one stays null, which clears it.

	QsMenuOpener {
		id: level0
		menu: menu.handle
	}

	QsMenuOpener {
		id: level1
		menu: menu.handleFor(1)
	}

	QsMenuOpener {
		id: level2
		menu: menu.handleFor(2)
	}

	QsMenuOpener {
		id: level3
		menu: menu.handleFor(3)
	}

	QsMenuOpener {
		id: level4
		menu: menu.handleFor(4)
	}

	function openerFor(level) {
		if (level === 0)
			return level0
		if (level === 1)
			return level1
		if (level === 2)
			return level2
		if (level === 3)
			return level3
		if (level === 4)
			return level4
		return null
	}

	// The entries of one column. The array is what a Repeater takes as a model,
	// and reading it here is what makes the columns follow the menu: both the
	// opener's children and `path` are read on every evaluation.
	function entriesFor(level) {
		var opener = openerFor(level)
		if (!opener || !opener.children || !opener.children.values)
			return []
		return opener.children.values
	}

	// The entry a column hangs off, which is both the submenu it should show and
	// what the level's opener is pointed at.
	function handleFor(level) {
		if (level <= 0)
			return handle
		var parent = entriesFor(level - 1)
		var index = path[level - 1]
		if (index === undefined || index < 0 || index >= parent.length)
			return null
		return parent[index]
	}

	// Where a row sits inside its column's content: the rows above it, each an
	// entry's height or a separator's rule plus its margin, offset by the box's
	// own border and padding.
	function rowOffsetInColumn(level, index) {
		var vals = entriesFor(level)
		var y = Theme.trayMenuBorderWidth + Theme.trayMenuPadV
		for (var i = 0; i < index && i < vals.length; i++) {
			y += vals[i].isSeparator === true
				? Theme.trayMenuSeparatorWidth + Theme.trayMenuSeparatorMargin * 2
				: Theme.trayMenuRowHeight
		}
		return y
	}

	// A submenu column hangs off the row that opened it rather than off the top
	// of the menu, the way a GTK submenu does: its top edge lines up with its
	// parent entry. Each column is offset by the one before it, so a cascade
	// three deep steps down with each step, the same as it steps right.
	function columnTopOffset(level) {
		if (level <= 0)
			return 0
		return columnTopOffset(level - 1) + rowOffsetInColumn(level - 1, path[level - 1])
	}

	readonly property int entryCount: entriesFor(0).length
	// The number of columns on screen: the menu, plus one per open submenu.
	readonly property int depth: Math.min(path.length + 1, Theme.trayMenuMaxDepth)

	// ── open / close ─────────────────────────────────────────────────────────

	function open() {
		path = []
		focused = -1
		cascadeMaxWidth = 0
		shown = true
	}

	function dismiss() {
		shown = false
	}

	// ── walking the cascade ──────────────────────────────────────────────────

	// Opens the submenu of a row, collapsing any column to the right of it
	// first. Called for a hover and for a click alike, which is what makes the
	// cascade follow the pointer as well as the keyboard.
	function descend(level, index) {
		if (level >= Theme.trayMenuMaxDepth - 1)
			return
		var next = path.slice(0, level)
		next.push(index)
		path = next
		focused = -1
	}

	// Closes every column to the right of `level`. Hovering an entry with no
	// children does this, so a cascade three deep folds back as soon as the
	// pointer settles on a leaf.
	function collapseTo(level) {
		if (path.length <= level)
			return
		path = path.slice(0, level)
		focused = -1
	}

	// The rows of the deepest column, in the order they are drawn, without the
	// separators and the disabled entries -- what the arrows step through.
	function navigable() {
		var list = []
		var values = entriesFor(depth - 1)
		for (var i = 0; i < values.length; i++) {
			var e = values[i]
			if (e.isSeparator === true || e.enabled === false)
				continue
			list.push(i)
		}
		return list
	}

	function move(delta) {
		var list = navigable()
		if (list.length === 0)
			return
		var at = list.indexOf(focused)
		if (at < 0)
			focused = list[delta > 0 ? 0 : list.length - 1]
		else
			focused = list[Math.min(Math.max(at + delta, 0), list.length - 1)]
	}

	function focusedEntry() {
		var values = entriesFor(depth - 1)
		return focused >= 0 && focused < values.length ? values[focused] : null
	}

	function activateFocused() {
		var e = focusedEntry()
		if (!e || e.isSeparator === true || e.enabled === false)
			return
		if (e.hasChildren === true) {
			descend(depth - 1, focused)
			return
		}
		if (e.sendTriggered)
			e.sendTriggered()
		dismiss()
	}

	// One column back, and the keyboard lands on the row that opened the column
	// being closed. From the first column, left means close.
	function ascend() {
		if (path.length === 0) {
			dismiss()
			return
		}
		focused = path[path.length - 1]
		path = path.slice(0, path.length - 1)
	}

	onShownChanged: shown ? menuOpened() : menuClosed()

	// Not `opened`/`closed`: the window base type already declares a `closed`
	// signal, and declaring either name again is a duplicate-signal error at load
	// time.
	signal menuOpened()
	signal menuClosed()

	// ── window ───────────────────────────────────────────────────────────────

	visible: shown
	screen: screenModel
	color: "transparent"

	// Full screen, so a click anywhere outside the box can close the menu. The
	// panel reserves no space, the way the bar and the notification centre do
	// not.
	anchors {
		top: true
		left: true
		right: true
		bottom: true
	}

	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore

	WlrLayershell.layer: WlrLayer.Top
	WlrLayershell.namespace: "quickshell:tray-menu"
	// The menu answers the keyboard while it is up: escape closes it, the arrows
	// walk the entries and the cascade. Never held while it is closed, or the
	// surface would keep the session's input after a close.
	WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

	// The box's own padding plus its border, on each side.
	readonly property real chromeX: Theme.trayMenuPadLeft + Theme.trayMenuPadRight + Theme.trayMenuBorderWidth * 2
	readonly property real chromeY: Theme.trayMenuPadV * 2 + Theme.trayMenuBorderWidth * 2

	// ── where the box goes ───────────────────────────────────────────────────
	//
	// The icon's rectangle, measured in the bar's own surface, plus the bar's
	// margins. `mapToItem(null, ...)` resolves against the bar's window, whose
	// origin is the bar surface's top-left -- and the bar surface sits at the
	// bar's margins in screen space, so adding them lands in screen coordinates.
	// The same offset was measured when the tooltips were anchored to their
	// modules.
	readonly property point anchorPoint: {
		// Read only so this binding depends on it: see geometryRevision above.
		var revision = geometryRevision
		if (revision < 0 || !target)
			return Qt.point(Theme.marginSide, Theme.marginTop)
		var p = target.mapToItem(null, 0, 0)
		return Qt.point(p.x + Theme.marginSide, p.y + Theme.marginTop)
	}

	// Left-aligned with the icon, just below the bar, and clamped so the box
	// (and any submenu open beside it) stays on screen rather than hanging off
	// an edge -- a menu that ran off the screen would be unusable. Recomputed
	// from the cascade's own size, which changes as columns open and close.
	readonly property real desiredX: anchorPoint.x
	readonly property real desiredY: anchorPoint.y + (target ? target.height : 0) + Theme.trayMenuGap

	// The widest the cascade has been while this menu has been open. Clamping
	// against the live width would make the menu slide left the moment a submenu
	// opened and back right the moment it closed -- and since a shift also moves
	// which row is under the pointer, that would fold the submenu away and start
	// the whole thing over. Taking the maximum once makes the placement settle.
	property real cascadeMaxWidth: 0

	function noteCascadeWidth(w) {
		if (w > cascadeMaxWidth)
			cascadeMaxWidth = w
	}

	// A click that lands on the menu's own background -- anywhere but a row --
	// shuts the menu, the way a click outside a GTK menu does.
	MouseArea {
		anchors.fill: parent
		onClicked: menu.dismiss()
	}

	// The key handler needs an item to live on, and it must be one that can hold
	// focus: the window's own content item cannot.
	FocusScope {
		id: keys

		anchors.fill: parent
		focus: menu.shown

		Keys.onEscapePressed: menu.dismiss()

		Keys.onPressed: function(event) {
			switch (event.key) {
			case Qt.Key_Down:
				menu.move(1)
				event.accepted = true
				break
			case Qt.Key_Up:
				menu.move(-1)
				event.accepted = true
				break
			case Qt.Key_Right:
				menu.activateFocused()
				event.accepted = true
				break
			case Qt.Key_Left:
				menu.ascend()
				event.accepted = true
				break
			case Qt.Key_Return:
			case Qt.Key_Enter:
			case Qt.Key_KP_Enter:
			case Qt.Key_Space:
				menu.activateFocused()
				event.accepted = true
				break
			}
		}
	}

	// ── the cascade ──────────────────────────────────────────────────────────

	Row {
		id: cascade

		onImplicitWidthChanged: menu.noteCascadeWidth(implicitWidth)

		x: Math.max(Theme.marginSide,
			Math.min(menu.desiredX, menu.width - Math.max(cascade.implicitWidth, menu.cascadeMaxWidth) - Theme.marginSide))
		y: Math.max(Theme.marginSide,
			Math.min(menu.desiredY, menu.height - cascade.implicitHeight - Theme.marginSide))

		Repeater {
			model: menu.depth

			// One column, drawn as its own rounded box: the cascade reads as a
			// menu with submenus beside it rather than as one wide box with
			// dividers. Columns are sized independently, so a long submenu is
			// wide without stretching the menu it came from.
			delegate: Item {
				id: column

				required property int index

				// The level this column draws: 0 is the menu, 1 the first
				// submenu, and so on.
				readonly property int level: column.index
				readonly property var values: menu.entriesFor(column.level)
				readonly property bool deepest: column.level === menu.depth - 1
				// Not readonly: the rows assign to it on hover, which is what breaks
				// the binding below and leaves the highlight following the pointer.
				property int hoveredRow: hoverRow.index

				// Which row the pointer is over, tracked by the rows themselves.
				QtObject {
					id: hoverRow
					property int index: -1
				}

				// Whether any entry in this column carries an icon. The icon
				// slot is then reserved on every row, so the labels line up
				// whether or not their own entry has one.
				readonly property bool anyIcon: {
					var vals = column.values
					for (var i = 0; i < vals.length; i++) {
						var e = vals[i]
						if (e.isSeparator !== true && e.icon && String(e.icon) !== "")
							return true
					}
					return false
				}

				readonly property real iconSlot: column.anyIcon
					? Theme.trayMenuIconSize + Theme.trayMenuIconGap : 0

				// The column's width comes from its widest label, measured --
				// not from the rows' widths, which read back from the column and
				// would be a sizing cycle (a Column's implicit width is the max
				// of its children's widths). The font is a monospace Nerd Font,
				// so the longest label is also the widest, and TextMetrics
				// measures it exactly.
				readonly property string widestLabel: {
					var best = ""
					var vals = column.values
					for (var i = 0; i < vals.length; i++) {
						var e = vals[i]
						if (e.isSeparator === true)
							continue
						var t = menu.stripLabel(e.text)
						if (t.length > best.length)
							best = t
					}
					return best
				}

				TextMetrics {
					id: colMetrics

					font.family: Theme.fontFamily
					font.pixelSize: Theme.fontSize
					text: column.widestLabel
				}

				readonly property real contentWidth: Math.min(
					colMetrics.advanceWidth + Theme.trayMenuCheckWidth + column.iconSlot + Theme.trayMenuArrowWidth,
					Theme.trayMenuMaxWidth - menu.chromeX)

				implicitWidth: Math.min(box.width, Theme.trayMenuMaxWidth)
				implicitHeight: box.height

				// Stepped down to line its top up with the row that opened it.
				transform: Translate {
					y: menu.columnTopOffset(column.level)
				}

				// Chrome, drawn the way the bar, the tooltips and the OSD draw
				// theirs: a filled rect in the border colour with the background
				// inset inside it, because Qt centres a border pen on the
				// outline and clips the outer half.
				Rectangle {
					id: box

					width: column.contentWidth + menu.chromeX
					height: content.implicitHeight + menu.chromeY
					radius: Theme.trayMenuRadius
					color: Theme.borderColor

					Rectangle {
						anchors.fill: parent
						anchors.margins: Theme.trayMenuBorderWidth
						radius: Math.max(Theme.trayMenuRadius - Theme.trayMenuBorderWidth, 0)
						color: menu.background
					}
				}

				Column {
					id: content

					x: Theme.trayMenuBorderWidth + Theme.trayMenuPadLeft
					y: Theme.trayMenuBorderWidth + Theme.trayMenuPadV
					width: column.contentWidth

					Repeater {
						model: column.values

						delegate: Item {
							id: row

							required property var modelData
							required property int index

							readonly property var entry: row.modelData
							readonly property bool separatorEntry: entry && entry.isSeparator === true
							readonly property bool hasSubmenu: !separatorEntry && entry.hasChildren === true
							readonly property bool usable: !separatorEntry && entry.enabled !== false
							// The keyboard selection and the row under the pointer
							// read the same way; the keyboard only has a say in
							// the deepest column.
							readonly property bool highlighted: !separatorEntry
								&& (column.hoveredRow === row.index || (column.deepest && menu.focused === row.index))

							readonly property string label: menu.stripLabel(entry ? entry.text : "")

							// The mark on a toggle entry. Check state is Qt's:
							// 0 unchecked, 1 partial, 2 checked.
							readonly property string checkGlyph: {
								if (separatorEntry || !entry || entry.buttonType === QsMenuButtonType.None)
									return ""
								if (entry.checkState !== Qt.Checked && entry.checkState !== Qt.PartiallyChecked)
									return ""
								return entry.buttonType === QsMenuButtonType.RadioButton
									? Icons.menuSelected : Icons.menuChecked
							}

							// A themed icon, or a path/url the application gave.
							// Quickshell.iconPath resolves a theme name and passes
							// a path through; an empty result means nothing to
							// draw, and the slot is left empty.
							readonly property string iconSource: {
								if (separatorEntry || !entry || !entry.icon)
									return ""
								var icon = String(entry.icon)
								if (icon.indexOf("/") === 0 || icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0)
									return icon
								return Quickshell.iconPath(icon, true)
							}

							width: content.width
							height: separatorEntry
								? Theme.trayMenuSeparatorWidth + Theme.trayMenuSeparatorMargin * 2
								: Theme.trayMenuRowHeight

							// A separator rule, spanning the column's inner width.
							Rectangle {
								anchors.verticalCenter: parent.verticalCenter
								width: parent.width
								height: Theme.trayMenuSeparatorWidth
								color: menu.muted
								opacity: 0.5
								visible: row.separatorEntry
							}

							// The hover/keyboard marker: a bar down the left edge
							// at text height, like every other list in this shell.
							Rectangle {
								anchors.left: parent.left
								anchors.verticalCenter: parent.verticalCenter
								width: Theme.trayMenuBarWidth
								height: Theme.trayMenuBarHeight
								color: menu.highlight
								visible: row.highlighted
							}

							// check slot · icon slot · label · arrow slot, in a Row
							// so each part is only as wide as it needs to be. The
							// slots are reserved on every row, which is what lines
							// the labels and the chevrons up.
							Row {
								id: lines

								anchors.left: parent.left
								visible: !row.separatorEntry
								height: parent.height
								spacing: 0

								Item {
									width: Theme.trayMenuCheckWidth
									height: lines.height

									Text {
										anchors.centerIn: parent
										text: row.checkGlyph
										color: row.highlighted ? menu.highlight : menu.foreground
										font.family: Theme.fontFamily
										font.pixelSize: Theme.fontSize
									}
								}

								Item {
									width: column.iconSlot
									height: lines.height

									Image {
										anchors.centerIn: parent
										width: Theme.trayMenuIconSize
										height: Theme.trayMenuIconSize
										source: row.iconSource
										// A theme icon that fails to resolve
										// leaves the slot empty rather than
										// showing Qt's broken-image box.
										visible: row.iconSource !== "" && status !== Image.Error
										fillMode: Image.PreserveAspectFit
										smooth: true
									}
								}

								Item {
									// What is left after the fixed slots: the
									// label elides into it.
									width: Math.max(0, column.contentWidth
										- Theme.trayMenuCheckWidth - column.iconSlot - Theme.trayMenuArrowWidth)
									height: lines.height

									Text {
										id: labelText

										anchors.verticalCenter: parent.verticalCenter
										width: parent.width
										text: row.label
										// A disabled entry is dimmed rather than
										// hidden, the way a menu shows what is
										// not available right now.
										opacity: row.usable ? 1 : 0.45
										color: row.highlighted && row.usable ? menu.highlight : menu.foreground
										font.family: Theme.fontFamily
										font.pixelSize: Theme.fontSize
										elide: Text.ElideRight
									}
								}

								Item {
									width: Theme.trayMenuArrowWidth
									height: lines.height

									Text {
										anchors.centerIn: parent
										text: row.hasSubmenu ? Icons.traySubmenu : ""
										color: row.highlighted ? menu.highlight : menu.muted
										font.family: Theme.fontFamily
										font.pixelSize: Theme.fontSize
									}
								}
							}

							// ── pointer ──────────────────────────────────────────
							//
							// Hover selects, exactly as in a GTK menu. A row with
							// children opens its column once the pointer has
							// settled on it -- held off briefly so sweeping down
							// the menu does not strobe submenus on the way past --
							// and a row without children folds the cascade back
							// immediately, which is cheap and is what the pointer
							// expects as soon as it lands on a leaf.

							MouseArea {
								anchors.fill: parent
								enabled: row.usable
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor

								onEntered: {
									column.hoveredRow = row.index
									if (row.hasSubmenu) {
										if (menu.path[column.level] !== row.index)
											openSubmenu.restart()
									} else {
										menu.collapseTo(column.level)
									}
								}

								onExited: {
									if (column.hoveredRow === row.index)
										column.hoveredRow = -1
									openSubmenu.stop()
								}

								onClicked: row.activate()
							}

							Timer {
								id: openSubmenu

								interval: Theme.trayMenuSubmenuDelay
								onTriggered: menu.descend(column.level, row.index)
							}

							function activate() {
								if (!row.usable)
									return
								if (row.hasSubmenu) {
									menu.descend(column.level, row.index)
									return
								}
								// The DBusMenu "clicked" event, the same one the
								// platform menu sends. The application answers by
								// doing the thing and, for a toggle, by publishing
								// a new layout.
								if (row.entry.sendTriggered)
									row.entry.sendTriggered()
								menu.dismiss()
							}
						}
					}
				}
			}
		}
	}
}
