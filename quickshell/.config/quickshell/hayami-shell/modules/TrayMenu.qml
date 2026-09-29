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
// Activating an entry is the application's, not ours: emitting an entry's
// triggered signal is the DBusMenu "clicked" event, the same one the platform
// menu sends. (See triggerEntry() for why it is not DBusMenuItem.sendTriggered.)
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
//	// A submenu is not a window of its own here. A QML component cannot instantiate
	// itself -- Quickshell rejects that outright -- so a menu that opened submenus as
	// nested windows would have to be a chain of files with a hard depth, each one
	// spawning the next. Instead the whole cascade is drawn in this one surface, a
	// column per open level, laid out side by side -- leftwards, except from a
	// left-edge bar (see growsLeft): the same thing a GTK menu shows, and it keeps
	// the submenu's columns from being pushed around by the screen edge
	// independently of the menu they belong to -- across the screen, at least. Down
// the screen each column is placed on its own, one row into the page from the row
// that opened it (see columnTopOffset), rather than the whole cascade being
// lifted to fit: a cascade longer than the space beside the icon has to give
// somewhere, and moving the menu column would move the row under the pointer.
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

	// Which edge of the screen the bar is on. It says where the surface's origin
	// sits in screen space (the bar is not always in the top-left corner) and
	// which way the menu has to leave the icon: down from a top bar, up from a
	// bottom one, and out to the side of a vertical one.
	required property string edge

	// A counter the bar bumps whenever the tray section moves, so the position
	// below is re-read. See TrayExpander.geometryRevision for why a binding cannot
	// simply call mapToItem and expect to be re-evaluated.
	required property int geometryRevision

	// Where the surface the icon lives in starts on the screen. The margins below
	// describe the *bar*, which is what an icon in the bar needs -- but a tray icon
	// lives in the tray panel's own surface (see TrayExpander), and that surface
	// sits off the side of the bar, so the panel hands its own origin down here
	// instead. A negative x means "an icon in the bar": nothing on screen starts
	// left of the screen.
	property point surfaceOrigin: Qt.point(-1, -1)

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

	// Where a column's top edge goes, in the cascade's own coordinates: 0 is the
	// menu's top edge, and everything below is measured from there.
	//
	// A submenu column hangs off the row that opened it. Each column is offset by
	// the one before it, so a cascade three deep steps down with each step, the
	// same as it steps right.
	//
	// Where exactly it hangs is a matter of taste, and the placements are tried
	// in this order, taking the first that fits on screen:
	//
	//   1. One row further into the page than the row that opened it: below the
	//      row from a top bar, above it from a bottom bar. That is the popout
	//      reading -- the submenu carries on out of the menu instead of sitting
	//      level with it -- and the one row of separation is what keeps it
	//      obviously that row's submenu. Only for a top or bottom bar: from a
	//      vertical bar a submenu comes out sideways, and there is no page
	//      direction to step into.
	//   2. Level with the row, the way a GTK submenu does: its top edge on the
	//      row's top, from any bar.
	//   3. On the row's other side, which is what a column too tall for the space
	//      it wanted needs -- above the row from a top bar, below it otherwise.
	//   4. Pinned to the top margin and clipped, for a column taller than the
	//      screen, where nothing fits.
	//
	// A column that would simply be lifted until it fit -- which is what this did
	// first -- ends up floating beside the menu with nothing to say which row
	// opened it, so every placement above is preferred to that.
	function columnTopOffset(level, columnHeight) {
		if (level <= 0)
			return 0
		var rowTop = rowTopInColumn(level)
		var rowBottom = rowTop + Theme.trayMenuRowHeight
		// The screen, in the cascade's coordinates: the cascade has already been
		// placed, so its own top edge is the origin both limits are measured
		// from, and the margin on each side is what is left for the columns.
		var topLimit = Theme.marginSide - cascade.y
		var lowestTop = menu.height - Theme.marginSide - cascade.y - columnHeight

		var wanted = [
			edge === "top" ? rowBottom : rowTop - columnHeight,
			rowTop,
			edge === "top" ? rowTop - columnHeight : rowBottom - columnHeight
		]
		// A vertical bar has no page side to step to, so it goes straight to the
		// two placements around its row.
		if (vertical)
			wanted[0] = wanted[1]

		for (var i = 0; i < wanted.length; i++) {
			if (wanted[i] >= topLimit && wanted[i] <= lowestTop)
				return wanted[i]
		}
		return topLimit
	}

	// The top of the row that opened a column: its parent column's top as drawn,
	// plus the rows above it inside that column.
	function rowTopInColumn(level) {
		if (level <= 0)
			return 0
		return drawnTopOffsetOf(level - 1) + rowOffsetInColumn(level - 1, path[level - 1])
	}

	// The top of a column as drawn. Not simply columnTopOffset of its level: a
	// parent that opened upwards has moved, and everything hanging off it moves
	// with it. The drawn columns are the only place the heights are known, so
	// the offset is recovered from them.
	function drawnTopOffsetOf(level) {
		return columnTopOffset(level, columnHeightAt(level))
	}

	// How tall a column is as drawn, or 0 before it exists. A column's height is
	// its own box: nothing outside it takes part.
	function columnHeightAt(level) {
		var item = columnRepeater.itemAt(level)
		return item ? item.implicitHeight : 0
	}

	// The same for a column's width, which the horizontal placement needs to know
	// where the menu column sits inside the cascade.
	function columnWidthAt(level) {
		var item = columnRepeater.itemAt(level)
		return item ? item.implicitWidth : 0
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
		// The menu is opened to be used, and the arrows are how the keyboard
		// uses it, so it comes up with its first entry already on -- the row the
		// down arrow would have landed on anyway, but without the press. Opening
		// it from the tray panel's grid is the case this is for: enter puts the
		// keyboard in the menu, ready to walk it.
		focusFirstEntry()
	}

	// The first entry that can actually be used, which is what "the first one"
	// means to the keyboard: the top of what navigable() hands move(), not the
	// top of the menu, so a leading separator or a disabled entry is stepped over
	// rather than shown as selected.
	function focusFirstEntry() {
		var list = navigable()
		focused = list.length > 0 ? list[0] : -1
	}

	// A menu whose tree arrives late, or is rebuilt underneath it. Only ever used
	// to fill in a menu that has no selection yet: a rebuild must not take the
	// highlight off the row the user is on.
	onEntryCountChanged: if (shown && focused < 0) focusFirstEntry()

	function dismiss() {
		shown = false
		// Let the columns go with the menu. An opener pointed at an entry is what
		// tells the application its submenu is showing (Quickshell refs the entry
		// and the DBusMenu "opened" event follows), so releasing them here is what
		// sends the matching "closed" -- a menu that kept them pointed would leave
		// the application believing its submenu was still up.
		path = []
		focused = -1
	}

	// ── activating an entry ──────────────────────────────────────────────────
	//
	// Activating an entry is the application's, not ours: Quickshell surfaces the
	// DBusMenu "clicked" event as the QsMenuEntry.triggered signal, which
	// DBusMenuItem forwards to the D-Bus call, so emitting it is the whole of it.
	//
	// Not DBusMenuItem.sendTriggered, which reads like the method to call but is
	// a private slot -- unreachable from QML, so `typeof entry.sendTriggered` is
	// undefined and a guarded call to it silently does nothing at all. That was
	// why clicking a menu entry used to have no effect; emitting the signal is
	// the documented way, and it is what the platform menu does underneath.
	function triggerEntry(entry) {
		if (!entry || entry.isSeparator === true || entry.enabled === false)
			return
		entry.triggered()
	}

	// Everything that activates a leaf entry comes through here -- the pointer's
	// click and the keyboard's enter alike -- so the menu always shuts with the
	// activation and the owner is always told about it.
	//
	// The menu shutting is the ordinary thing a menu does. Telling the owner is the
	// tray's: this menu hangs off an icon inside TrayExpander's panel, and an entry
	// that opens an application should leave the screen to that application. A panel
	// still sitting in its corner would cover what was just opened, and in keyboard
	// mode it would be holding the session's keyboard as well, so it would have to
	// be dismissed by hand before the application could be used at all.
	function activateEntry(entry) {
		if (!entry || entry.isSeparator === true || entry.enabled === false)
			return
		triggerEntry(entry)
		dismiss()
		entryActivated()
	}

	// ── walking the cascade ──────────────────────────────────────────────────

	// Opens the submenu of a row, collapsing any column beyond it first. Called
	// for a hover and for a click alike, which is what makes the cascade follow
	// the pointer as well as the keyboard.
	function descend(level, index) {
		if (level >= Theme.trayMenuMaxDepth - 1)
			return
		var next = path.slice(0, level)
		next.push(index)
		path = next
		focused = -1
	}

	// Closes every column deeper than `level`. Hovering an entry with no children
	// does this, so a cascade three deep folds back as soon as the pointer settles
	// on a leaf.
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
		activateEntry(e)
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

	onShownChanged: shown ? menuOpened() : menuClosed()	// Not `opened`/`closed`: the window base type already declares a `closed`
	// signal, and declaring either name again is a duplicate-signal error at load
	// time.
	signal menuOpened()
signal menuClosed()

	// A leaf entry was activated: the application has been sent its click. Not
	// a submenu opening, which stays inside the menu. The owner shuts the tray
	// panel on this -- see activateEntry().
	signal entryActivated()

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
	// The icon's rectangle, measured in the surface it lives in, plus that
	// surface's own origin in screen space. `mapToItem(null, ...)` resolves
	// against the window the icon belongs to -- the bar's, or the tray panel's
	// when the icon came out of there -- and that is the surface's top-left.
	//
	// For the bar that origin is the screen's own: Bar.qml's surface is the whole
	// monitor on every edge, so a window coordinate *is* a screen coordinate and
	// there is no margin to add back. The panel is a layer surface of its own at
	// panelX/panelY, so it hands its origin down through surfaceOrigin.
	// The same offset was measured when the tooltips were anchored to their
	// modules.
	readonly property bool vertical: edge === "left" || edge === "right"
	readonly property real thickness: Theme.thicknessFor(edge)

	readonly property point origin: {
		// An icon in the tray panel: the panel says where it is, because its
		// origin is not the screen's -- it is a layer surface of its own.
		if (surfaceOrigin.x >= 0)
			return surfaceOrigin
		// An icon in the bar: the bar's surface is the screen (see Bar.qml), so
		// its window coordinates are already screen coordinates.
		return Qt.point(0, 0)
	}

	readonly property point anchorPoint: {
		// Read only so this binding depends on it: see geometryRevision above.
		var revision = geometryRevision
		if (revision < 0 || !target)
			return origin
		var p = target.mapToItem(null, 0, 0)
		return Qt.point(p.x + origin.x, p.y + origin.y)
	}

	// Off the far side of the icon -- down from a top bar, up from a bottom one,
	// and out to the side of a vertical one -- and clamped so the box (and any
	// submenu open beside it) stays on screen rather than hanging off an edge; a
	// menu that ran off the screen would be unusable.
	//
	// The whole cascade is offset rather than just the first column, because the
	// columns run end to end: the box's near edge is the one that has to sit by
	// the icon, and when the cascade grows leftwards that is the row's *right*
	// end.
	readonly property real cascadeSize: Math.max(cascade.implicitWidth, cascadeMaxWidth)

	// How tall the menu's own column is -- the one beside the icon -- as drawn.
	//
	// This, and not the tallest column in the cascade, is what the menu is placed
	// by. A submenu is usually taller than the menu it hangs off, and letting
	// that height lift the menu would slide every row out from under the pointer
	// the moment the submenu opened -- and the row that moved into its place has
	// no children, so the submenu would fold away again and the pair of them
	// would flicker. Submenus are kept on screen by the clamp on each column
	// instead: see columnTopOffset.
	readonly property real menuColumnHeight: {
		var own = columnHeightAt(0)
		return own > 0 ? own : cascade.implicitHeight
	}

	// How wide the menu's own column is, for the same reason as its height: it is
	// the column that has to stay where the icon put it, whichever way the
	// submenus run off it.
	//
	// Reading the row is what makes it re-evaluate once the columns exist --
	// itemAt() on its own is not a property dependency, so a version that only
	// asked for the column would read 0 and stay 0, and the menu would land a
	// column's width away from the icon. Same shape as menuColumnHeight above.
	readonly property real menuColumnWidth: {
		var own = columnWidthAt(0)
		return own > 0 ? own : cascade.implicitWidth
	}

	// Which way the cascade grows away from the menu column.
	//
	// Only a left-edge bar runs its submenus to the *right*: there the menu
	// itself sits just right of the icon, so right is the way into the screen. On
	// every other edge left is: a right-edge bar already has the menu hugging that
	// edge, and a top or bottom bar has its tray at the right end of the bar, so a
	// submenu opened to the right would immediately be against the screen edge
	// (and the whole cascade would have to be shoved back inwards to fit).
	readonly property bool growsLeft: edge !== "left"

	readonly property real desiredX: {
		if (edge === "left")
			return anchorPoint.x + (target ? target.width : 0) + Theme.trayMenuGap
		// The cascade runs left, so the menu column is the rightmost one in the
		// row. What the icon pins is where that column sits -- its right edge just
		// clear of the icon on a right-edge bar, its left edge on the icon's own x
		// from a top or bottom bar -- and the row's left edge is the rest of the
		// way left: the live width of the cascade, less the menu column itself.
		//
		// *Live*, unlike the x clamp below, which deliberately holds the widest the
		// cascade has been. Placing the row from that widest figure instead would
		// leave the menu holding the offset its submenu needed: the moment the
		// submenu closed, the row would narrow again and the menu would be left
		// hanging a submenu's width away from its icon.
		var menuLeft = edge === "right"
			? anchorPoint.x - Theme.trayMenuGap - menuColumnWidth
			: anchorPoint.x
		return menuLeft + menuColumnWidth - cascade.implicitWidth
	}

	readonly property real desiredY: {
		if (edge === "bottom")
			return anchorPoint.y - menuColumnHeight - Theme.trayMenuGap
		if (vertical)
			return anchorPoint.y
		return anchorPoint.y + (target ? target.height : 0) + Theme.trayMenuGap
	}

	// The width the placement is measured against, and the reason there are two
	// answers for it.
	//
	// From a left-edge bar the row's left edge *is* the menu column, so a clamp
	// that followed the live width would drag the menu sideways the moment a
	// submenu opened -- and a sideways shift moves which row is under the pointer,
	// which closes the submenu again and starts the whole thing over. Clamping
	// against the widest the cascade has been settles that: the bound moves once,
	// and never back.
	//
	// Everywhere else the menu column is pinned by the icon and the submenus run
	// off behind it (see growsLeft, desiredX), so nothing is being dragged: what
	// is left is the row hugging the width it actually has. Measuring that from
	// the widest figure instead is what leaves a menu hanging a submenu's width
	// away from its icon once the submenu closes.
	readonly property real placementWidth: growsLeft ? cascade.implicitWidth : cascadeSize

	// The widest the cascade has been while this menu has been open. Only read
	// through placementWidth, above.
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
			// The arrows and hjkl are the same four moves, so the menu is driven
			// the way every other list in this shell is.
			case Qt.Key_Down:
			case Qt.Key_J:
				menu.move(1)
				event.accepted = true
				break
			case Qt.Key_Up:
			case Qt.Key_K:
				menu.move(-1)
				event.accepted = true
				break
			case Qt.Key_Right:
			case Qt.Key_L:
				menu.activateFocused()
				event.accepted = true
				break
			case Qt.Key_Left:
			case Qt.Key_H:
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

		// Growing leftwards, the menu itself is the rightmost column -- the one
		// beside (or under) the icon -- and its submenus open to its left: see
		// growsLeft for which edges do that.
		layoutDirection: menu.growsLeft ? Qt.RightToLeft : Qt.LeftToRight

		onImplicitWidthChanged: menu.noteCascadeWidth(implicitWidth)

		x: Math.max(Theme.marginSide,
			Math.min(menu.desiredX, menu.width - menu.placementWidth - Theme.marginSide))
		y: Math.max(Theme.marginSide,
			Math.min(menu.desiredY, menu.height - menu.menuColumnHeight - Theme.marginSide))

		Repeater {
			id: columnRepeater

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

				// Stepped down to line its top up with the row that opened it, or
				// up from it when it would not fit below: see columnTopOffset.
				//
				// Only the column moves, never the cascade. Sliding the menu
				// column to make room would put a different row under the
				// pointer, and a row without children closes the submenu it was
				// meant to open, so the two of them would flicker.
				readonly property real drawnTopOffset:
					menu.columnTopOffset(column.level, box.height)

				transform: Translate {
					y: column.drawnTopOffset
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
								// platform menu sends, and the close that follows it.
								menu.activateEntry(row.entry)
							}
						}
					}
				}
			}
		}
	}
}
