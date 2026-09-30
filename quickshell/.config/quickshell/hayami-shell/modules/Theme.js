.pragma library

// Design tokens for the Quickshell top bar.
//
// These values were carried over 1:1 from the stylesheet and config the bar
// replaced, so it kept its look instead of becoming something new. That source
// is gone now, which makes these the only copy -- so the comment beside each
// value says what it is meant to match.

// "height": 26, "margin": "6 12 0 12", "spacing": 8
var height = 26
var marginTop = 6
var marginSide = 12
var spacing = 8

// ── edges ────────────────────────────────────────────────────────────────────
//
// The bar can sit on any of the four edges (BarState.position). On the left and
// right its 26px height becomes its *thickness* and the modules stack instead of
// running end to end, so "thickness" is the one word for both the height of a
// horizontal bar and the width of a vertical one:
//
//   horizontal: thickness = height, marginTop to its edge
//   vertical:   thickness = the value below, marginTop to its edge
//
// marginTop and marginSide keep their meanings on every edge: the gap to the
// edge the bar is on, and the gaps at its two ends. They place the bar's *strip*
// inside its surface rather than placing the surface itself, because the surface
// is the whole monitor on every edge (see Bar.qml).

// A vertical bar is 6px thicker than a horizontal one is tall. The 26px height
// was measured off a horizontal bar, where nothing has to fit *across* it; on a
// vertical bar the same 26px is what a module's glyph and value have to fit in.
// 32 leaves a 26px well between the padding below, which is a whole "100%" at
// the value size -- the widest text any module puts on its own line.
var verticalThickness = 32

// What is left of a vertical bar's width for a module once the padding is off
// it. Every module is this width, so the modules line up down the bar.
var verticalPadding = 3
var verticalWell = verticalThickness - verticalPadding * 2

// The value line of a module on a vertical bar, under its glyph. Smaller than
// the glyph because it is read as a value rather than as the module: at 12px a
// three-character "100%" is wider than the well, and at 10px it is 24 of the
// 26px. The glyph keeps the bar's own size, so the icons still read as icons.
var verticalValueSize = 10

// The gap between stacked modules. The 8px spacing was measured between modules
// that share one row; stacked, the modules' own leading/trailing margins already
// hold them apart (12px, since every status module carries 6px either side),
// so this only has to keep neighbours from touching.
var verticalSpacing = 4

// The bar's thickness on the edge it is on. Every geometry rule that needs the
// bar's own size reads this rather than `height`, so a vertical bar is one
// substitution away from the horizontal one rather than a second layout.
function thicknessFor(edge) {
	return (edge === "left" || edge === "right") ? verticalThickness : height
}

function isVertical(edge) {
	return edge === "left" || edge === "right"
}

// { border: 1.2px solid #444444; border-radius: 8px; opacity: 0.9 }
var radius = 8
var borderWidth = 1.2

var borderColor = "#444444"
var barOpacity = 0.9

// * { font-family: 'JetBrainsMono Nerd Font'; font-size: 12px }
var fontFamily = "JetBrainsMono Nerd Font"
var fontSize = 12


// .modules-left/.modules-right { margin: 0 8px }
var sectionPadding = 8

// #custom-tiling-direction.auto { opacity: 0.65 }
var dimAuto = 0.65
// #workspaces button.empty { opacity: 0.5 }
var dimEmpty = 0.5

// @keyframes blink { to { color: #a55555 } } animation: blink 1.5s infinite alternate
var pulseColor = "#a55555"
var pulseDuration = 1500

// ── the tray ────────────────────────────────────────────────────────
//
// The status notifier icons live in a panel of their own, off the side of the
// bar, rather than in a drawer that opened along it: the chevron is a module in
// the bar's row and never moves, and the icons are a flyout beside it. #tray
// { icon-size: 12 } still sizes the icons -- the rest is the panel's own chrome,
// drawn the way the tooltips are.
var trayIconSize = 12
// The square each icon sits in, and the gap between the squares. The square is
// the click target, which is what makes it worth having: a bare 12px icon is a
// small thing to hit.
var trayPanelCell = 26
var trayPanelSpacing = 4
// Across, before the grid wraps. Four keeps the panel narrower than a tooltip.
var trayPanelColumns = 4
var trayPanelPad = 8
var trayPanelRadius = 8
var trayPanelBorderWidth = 1.2
// Where the keyboard is, when the panel was opened from the launcher: an accent
// outline around the focused icon, inset far enough to sit inside its square
// rather than in the gap to its neighbour.
var trayPanelFocusInset = 1
var trayPanelFocusRadius = 5
var trayPanelFocusBorderWidth = 1.6
// The air between the bar and the panel. The gap is deliberately small: the
// pointer has to cross it to reach the panel, and the close delay below is what
// covers the crossing.
var trayPanelGap = 6
// How long the panel waits after the pointer leaves before folding away -- long
// enough to cross that gap, short enough not to feel sticky.
var trayPanelCloseDelay = 150
// The caret's half turn when the panel opens.
var trayPanelFlipDuration = 250

// ── tooltips ─────────────────────────────────────────────────────────────────
//
// These are GTK tooltips, so the behaviour below is GTK's and not
// the bar's: a tooltip appears below the module after GTK's tooltip delay, goes
// away the moment the pointer leaves, and is taken away after GTK's tooltip
// timeout even if the pointer has not moved. style.css overrides only their
// padding (`tooltip { padding: 2px }`); everything else comes from the GTK
// theme, which has no counterpart here -- so the colours are the bar's own and a
// tooltip reads as part of the shell rather than as a stray GTK popup.

// ── moving the bar ───────────────────────────────────────────────────────────
//
// The bar is dragged to another edge by pressing its own background (the gap
// between module groups; the modules keep their clicks) and releasing on the
// edge you want. What is drawn while the drag is live is a ghost of the bar in
// the place it would land.

// How far the pointer has to travel from where it was pressed for the release
// to count as a drag. A press that never moves is a click on the bar's
// background, which is nothing at all -- it must not move the bar to whichever
// edge the pointer happened to be nearest.
var dragThreshold = 16

// How far past the halfway line the pointer has to travel before the edge the
// drag will land on changes. Near the middle of the screen two edges are equally
// near and a hand is never quite still, so without it the target flips several
// times a second: measured through the shell's own IPC, 22 changes in 40 samples
// held within ±12px of the middle, and each change redraws the ghost on the
// other edge -- a full-length band of accent appearing and vanishing, which is
// what the middle of a drag looked like it was flashing. It also makes the drop
// there a coin toss between the two edges. Wider than `dragThreshold` on
// purpose: that one decides whether a press moved at all, this one decides which
// side of the middle it settled on.
var dragHysteresis = 24

// The ghost's border and fill while a drag is live. The fill is the accent, so
// the preview reads as "this is where the bar goes" rather than as a window
// outline; both are transparent enough to see the desktop through.
var dragPreviewRadius = 8
var dragPreviewBorderWidth = 2
var dragPreviewFillAlpha = 0.22
var dragPreviewBorderAlpha = 0.85

// How much of its own opacity the bar keeps while it is being dragged, so the
// bar itself reads as the thing that is moving.
var dragDim = 0.55

// GTK's gtk-tooltip-delay default (500ms).
var tooltipDelay = 500
// GTK's gtk-tooltip-timeout default (5s).
var tooltipTimeout = 5000
// style.css: tooltip { padding: 2px }. Horizontal is wider because the text is
// one line far more often than not, and a 2px left/right inset on a single line
// reads as no inset at all.
var tooltipPaddingX = 8
var tooltipPaddingY = 3
var tooltipRadius = 6
var tooltipBorderWidth = 1
var tooltipFontSize = 12
// GTK wraps a tooltip's text rather than letting it grow the full width of the
// screen, which is what the update module's package list needs.
var tooltipMaxWidth = 400
// The gap between the module and the tooltip below it.
var tooltipGap = 4

// ── tray context menus ───────────────────────────────────────────────────────
//
// A tray item's right-click menu, drawn by the shell rather than by
// QsMenuAnchor. The anchor renders a platform QMenu, which needs Quickshell in
// QApplication mode; this is the same menu the application publishes over
// DBusMenu, in the shell's own chrome -- box, type and hover highlight matching
// the tooltips and the launcher, so a menu reads as part of the bar.

// The same rounded box the tooltips and the OSD use.
var trayMenuRadius = 6
var trayMenuBorderWidth = 1
// Style.css has no counterpart: GTK menus are entirely theme-drawn. These are
// the padding (inside the border) and the row height that make a menu read like
// a menu rather than a list.
var trayMenuPadV = 4
var trayMenuPadLeft = 8
var trayMenuPadRight = 8
var trayMenuRowHeight = 22
// The slot the check/radio mark sits in, reserved on every row so labels line
// up whether or not their row has one.
var trayMenuCheckWidth = 14
var trayMenuIconSize = 14
var trayMenuIconGap = 8
// The slot the submenu chevron sits in, likewise reserved on every row.
var trayMenuArrowWidth = 16
// The hover marker: a bar down the row's left edge, the same cue the launcher
// and the other menus use, at text height rather than row height.
var trayMenuBarWidth = 2
var trayMenuBarHeight = 14
var trayMenuSeparatorWidth = 1
// Air above and below a separator rule.
var trayMenuSeparatorMargin = 4
// Wrapping width for a long entry; a menu that ran off the screen edge would be
// unusable, so the label elides instead.
var trayMenuMaxWidth = 360
// The gap between the tray icon and the menu below it, and between a row and
// the submenu beside it.
var trayMenuGap = 4
// A submenu opened by hover is held off briefly, so sweeping the pointer down a
// menu does not strobe submenus on the way past. Closing one is immediate: the
// columns sit flush, so there is no gap for the pointer to cross.
var trayMenuSubmenuDelay = 200
// How many columns a menu may cascade into: the menu itself plus its submenus.
// Five is well past what any real tray menu asks for (Zoom, the deep one here,
// uses two) and keeps the openers below a fixed, declarable set -- a menu cannot
// instantiate itself in QML, so the columns are openers rather than windows.
var trayMenuMaxDepth = 5

// ── the clock's calendar ─────────────────────────────────────────────────────
//
// The popout the clock opens, and the one place on the bar where the type scale
// deliberately leaves the bar's own: a month grid is read at a glance, so the
// hero date is much larger than anything the bar draws, and the rest sits at
// the bar's size or a shade under it.
//
// The box is the same rounded rect as the tray panel -- one chrome for every
// flyout on the bar.
var calendarRadius = 8
var calendarBorderWidth = 1.2
var calendarPad = 10
// A day cell, and the week-number gutter to its left. The grid is seven cells
// and six gaps wide plus the gutter, which is what the panel's width comes out
// at -- see CalendarPanel.
var calendarCellWidth = 30
var calendarCellHeight = 26
var calendarCellSpacing = 2
// The corner on a day cell: only the outline today wears one, so this is the
// grid's rounding rather than a per-cell decoration.
var calendarCellRadius = 5
var calendarWeekWidth = 26
var calendarGutter = 8
// The hero date and the two rails (year progress, and the life rail under it).
var calendarHeroSize = 26
var calendarRailHeight = 6
var calendarMonthSize = 12
// The one figure that runs vertically through the whole panel: between the
// hero and the year rail, between the rails and the grid, and between the grid
// and the month stepper under it. One number rather than three, so the panel
// reads as one column of blocks.
var calendarGap = 10
// The hover highlight on the hero date and the "W" heading, the same bar-down-
// the-left-edge cue every other list in the shell uses, at text height.
var calendarMarkWidth = 2
var calendarMarkHeight = 14
// How far off the bar the panel starts. The tray panel's gap, because every
// flyout on this bar begins the same distance from it.
var calendarBarGap = trayPanelGap

// ── driving the bar from the keyboard ────────────────────────────────────────
//
// The ring around the module the keyboard is on. The colour is the palette's
// own accent (see Bar.qml) rather than anything here -- what is here is the
// shape: an outline drawn just outside the module's own rectangle, so the ring
// reads as around the module and not as a second border inside it.
var barFocusInset = 2
var barFocusBorderWidth = 1.6
var barFocusRadius = 6

// ── the VPN popout ───────────────────────────────────────────────────────────
//
// The VPN indicator's flyout. It is the same box as the calendar's -- one chrome
// for every popout off the bar -- so the pieces the two share alias the
// calendar's values rather than repeating the numbers, and only what is this
// panel's own is written out here.
//
// The width is fixed, unlike the calendar's content-sized one: a hostname, an
// address and a row label all change under it, and a box that resized as the VPN
// came and went would read as the box moving rather than the reading.
var vpnPanelWidth = 232
var vpnPanelRadius = calendarRadius
var vpnPanelBorderWidth = calendarBorderWidth
var vpnPanelPad = calendarPad
var vpnPanelBarGap = calendarBarGap
// The panels' one vertical figure, used twice: between the reading and the action
// under it, and between the name and the state line inside the reading.
var vpnPanelGap = 12
var vpnPanelLineGap = 4
// The name is the panel's headline, a step under the calendar's hero date: a
// hostname is a longer string than a date and does not want the size of one.
var vpnPanelNameSize = 16
// The state line and the row under it, at the bar's own size.
var vpnPanelStatusSize = 12
var vpnPanelRowHeight = 26
// The dot that carries the state, beside the word for it.
var vpnPanelDotSize = 7
// The focus mark: the bar down the left edge every other list in the shell marks
// its focused row with, at the calendar's size.
var vpnPanelMarkWidth = calendarMarkWidth
var vpnPanelMarkHeight = calendarMarkHeight

// ── the agent popout ─────────────────────────────────────────────────────────
//
// The agent indicator's flyout: what the agent is doing and what it is spending.
// Same chrome as the calendar and the VPN panel, so the pieces that are shared
// alias those values rather than repeating the numbers.
//
// Wider than the VPN panel: the reading is a small table of label/value rows
// rather than one name and one line.
var agentPanelWidth = 268
var agentPanelRadius = calendarRadius
var agentPanelBorderWidth = calendarBorderWidth
var agentPanelPad = calendarPad
var agentPanelBarGap = calendarBarGap
var agentPanelGap = vpnPanelGap
// The headline, at the calendar's date size -- deliberately the same token, so
// the two popouts that name themselves cannot drift apart. Every other line in
// this block points somewhere on its own; this one is a decision that the agent
// card and the calendar share, and it is here rather than in the panel so that
// changing the type of a popout's heading is still one edit in one place.
var agentPanelNameSize = calendarHeroSize

// The hairline between a popout's heading and the readings under it. One pixel,
// spanning the card's inner width.
//
// The mix is a share rather than a colour: each panel draws it in *its* own
// foreground, pulled towards its own background, so a rule over a light palette
// and a rule over a dark one are the same rule and not the same grey. The air
// above and below it is the column's own spacing, not a margin here -- a rule
// with its own margin would sit at a different distance from the heading in each
// card, which is the thing a shared rule is supposed to prevent.
var panelDividerWidth = 1
var panelDividerMix = 0.72
// The rows and their labels, at the bar's own size.
var agentPanelStatusSize = vpnPanelStatusSize
// The provider's name, four pixels above the state beside it. In terms of the
// status size rather than a number of its own, because the relationship is the
// point: the name sits above the readings it heads, and saying so as an offset
// keeps it there if the status size ever moves.
//
// The one and two pixel steps were both too small to read as deliberate --
// they landed between two sizes rather than on either. At four it is 16, which
// is also vpnPanelNameSize: the size this shell gives the name of a thing in a
// panel, which is exactly what this is. That is a coincidence worth knowing
// about rather than a second reason, so it is still written as an offset; say
// the word and it becomes vpnPanelNameSize outright.
//
// It is still the dimmed tone, not the foreground. At this size the brightness
// would be the loudest thing in the readings, and the session rows are what the
// card is opened to read.
var agentPanelProviderSize = agentPanelStatusSize + 4
var agentPanelLabelSize = 11
var agentPanelRowHeight = 22
// The daily-allowance meter: a track with a fill across the panel's width.
var agentPanelMeterHeight = 6
var agentPanelMeterRadius = 3
// The dot that carries live/idle, beside the word for it.
var agentPanelDotSize = vpnPanelDotSize
// The air between a session row's waiting badge and the model's name beside it.
// Reserved whether the badge is there or not, so that a turn ending does not
// shift the row's own text (the same reason BarItem has a min-width).
var agentPanelBadgeGap = 6
var agentPanelMarkWidth = calendarMarkWidth
var agentPanelMarkHeight = calendarMarkHeight
