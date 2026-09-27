.pragma library

// Design tokens for the Quickshell top bar.
//
// Every value here was lifted 1:1 from the waybar style.css and config.jsonc this
// replaces, so the bar kept the waybar look instead of becoming something new.
// That package is gone now, which makes these the only copy -- the comments
// beside each value keep the old reference so it is still clear where a number
// came from and what it is meant to match.

// Waybar: "height": 26, "margin": "6 12 0 12", "spacing": 8
var height = 26
var marginTop = 6
var marginSide = 12
var spacing = 8

// #waybar { border: 1.2px solid #444444; border-radius: 8px; opacity: 0.9 }
var radius = 8
var borderWidth = 1.2

// Physical pixels the compositor's surface box comes up short at the bottom edge.
// The chrome insets its fill by this (converted to logical px with the monitor
// scale) so the bottom border band matches the other three sides.
var lostBottomPx = 1
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

// #tray { icon-size: 12, spacing: 17 }, drawer transition-duration: 600
var trayIconSize = 12
var traySpacing = 17
var trayDrawerDuration = 600

// ── tooltips ─────────────────────────────────────────────────────────────────
//
// waybar's tooltips are GTK tooltips, so the behaviour below is GTK's and not
// waybar's: a tooltip appears below the module after GTK's tooltip delay, goes
// away the moment the pointer leaves, and is taken away after GTK's tooltip
// timeout even if the pointer has not moved. style.css overrides only their
// padding (`tooltip { padding: 2px }`); everything else comes from the GTK
// theme, which has no counterpart here -- so the colours are the bar's own and a
// tooltip reads as part of the shell rather than as a stray GTK popup.

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
