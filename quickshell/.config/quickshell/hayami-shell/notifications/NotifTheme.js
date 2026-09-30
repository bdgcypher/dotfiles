.pragma library

// Design tokens for notifications.
//
// Colours are pywal names (@foreground, @color1, @color6, ...) resolved through
// BarPalette, so a wallpaper change re-tints notifications too. The geometry and
// spacing follow the panel's own rhythm rather than a formula, and the handful of
// sizes a toolkit would otherwise have decided for us (where the popup card
// actually lands, how tall a row is) were measured off a live window with
// `hyprctl layers -j` plus grim crops -- which is why they are odd numbers.

// ── the surface the popups live on ───────────────────────────────────────────

// "notification-window-width": 400, positioned right/top.
var popupWidth = 400

// Where the first card's top edge lands: the 38px padding-top of
// .floating-notifications plus the 16px margin-top every .notification-row
// carries. Measured on the live window: the first card's border starts at
// logical y 53.2 on a 982-tall screen.
var popupTop = 54

// .floating-notifications { padding-top: 38px } plus
// .floating-notifications .notification-row { margin: 16px 24px 0 0 } -- so the
// card's left edge is 24 in from the surface and the first card starts 54 down.
// Measured on the live window: card inset 16 from the top of the surface area and
// 24 from the right, 376 wide.
var popupPaddingTop = 38
var popupRowTop = 16
var popupRowRight = 24
var popupRowGap = 16

// ── a notification ───────────────────────────────────────────────────────────

// "transition-time": 200 (ms) -- used for popups appearing and disappearing and
// for the hovers below.
var transition = 200

// "notification-icon-size": 48
var iconSize = 48
// "notification-body-image-height"/"width": 160/200
var bodyImageHeight = 160
var bodyImageWidth = 200

// .notification { padding: 6px } and .notification-content { margin: 14px }, so a
// card's text sits 20 in from its own edge.
var cardPadding = 6
var cardContentMargin = 14
var cardRadius = 8
var cardBorderWidth = 2

// .image { margin: 10px 20px 10px 0 }
var iconMarginTop = 10
var iconMarginRight = 20
var iconMarginBottom = 10

// `.notification > *:last-child > * { min-height: 3.4em }`, at the 14px base font.
// This is what keeps a text-only card from collapsing: measured live, a card
// with no icon is 93 tall against 112 with a 48px one, and
// 2*2 + 2*(20 + max(47.6, 48+20)) gives exactly those two numbers.
var contentMinHeight = 47.6

// Inside the card's own 2px border. The popup has .notification padding 6 plus
// .notification-content margin 14 on all sides. The centre has .notification
// padding 4 plus margin 6, and then .notification-content's own `padding: 4px
// 6px 2px 2px` -- which is why its two sides are not the same:
//
//   popup   2 + 6 + 14 + content + 14 + 6 + 2 = content + 44
//   centre  2 + 4 + 6 + 4 + content + 2 + 6 + 4 + 2 = content + 30
//
// Both check out against the live panels (a 48px icon card measures 111.8
// against 112.7 in a popup, and 98 against 96.4 in the centre).
var popupPad = 20
var centerPadTop = 14
var centerPadBottom = 12
var centerPadSide = 10

// .summary { font-weight: 800; font-size: 1rem } / .body { font-size: 0.8rem }
var fontFamily = "JetBrainsMono Nerd Font"
var fontSize = 14
// font-weight: 800. A number rather than Font.ExtraBold, which is a QML enum and
// not visible from a .pragma library file.
var summaryWeight = 800
var bodySize = 11

// .close-button { margin: 6px; padding: 2px; border-radius: 6px }
var closeSize = 22
var closeMargin = 6
var closeRadius = 6

// The action row: .notification > *:last-child > * { min-height: 3.4em } with
// .notification-action { border-radius: 8px; margin: 6px; border: 1px solid
// transparent }, so 3.4 * 14 rounded to a whole number of pixels.
var actionRowHeight = 48
var actionRadius = 8
var actionMargin = 6
// GTK's default button padding, so an action is as wide as its label plus this.
var actionPadding = 12

// ── timeouts ─────────────────────────────────────────────────────────────────

// Timeouts are the panel's own, not the notification's -- 0 means "stay until
// dismissed".
var timeoutNormal = 5000
var timeoutLow = 3000
var timeoutCritical = 0

// A popup's timeout pauses while the pointer is over it.
var hoverPausesTimeout = true

// ── the control centre ───────────────────────────────────────────────────────

// "control-center-width": 380 and "control-center-height": 860 describe the
// widget, not what lands on screen. Measured off the live panel:
//
//   card    408 wide (380 + 2*12 padding + 2*2 border), 879 tall on a 982-tall
//           screen -- the height is the screen less the 50/51 margins, so the
//           notification list is what flexes, not the card
//   edges   right 25 from the screen edge, 52 from the top, 51 from the bottom
//           (the config's margin-top/bottom 2 and margin-right 1, plus
//           central_control.css's `margin: 50px 24px`)
//   window  432 wide -- the card plus its 24px right margin -- and full height
var centerCardWidth = 408
var centerWidth = 432
var centerHeight = 860
var centerMarginTop = 2
var centerMarginBottom = 2
var centerMarginRight = 1

// .control-center { margin: 50px 24px; padding: 12px; border: 2px solid }
var centerCardMarginTop = 50
var centerCardMarginBottom = 50
var centerCardMarginRight = 24
var centerCardPadding = 12

// The 10 buttons of the buttons grid. The glyphs are nerd-font codepoints pasted
// as escapes because they are invisible in an editor.
var gridButtons = [
	{ glyph: "\uDB81\uDE6A", command: ["ghostty", "--class=floating.Wiremix", "-e", "wiremix"] },
	{ glyph: "\uF1EB", command: ["ghostty", "--class=floating.Gazelle", "-e", "gazelle"] },
	{ glyph: "\uDB80\uDCAF", command: ["ghostty", "--class=floating.Bluetui", "-e", "bluetui"] },
	{ glyph: "\uDB80\uDFD8", command: ["ghostty", "--class=floating.Wallpaper", "-e", "set-custom-wallpaper"] },
	{ glyph: "\uF011", command: ["hayami-menu", "-m", "menus:system/power", "--width", "250"] },
	{ glyph: "\uDB81\uDF5D", command: ["ghostty", "--class=floating.VolumeBoost", "-e", "volume-boost-toggle"] },
	// The config pipes hyprshot into satty, so this one needs a shell.
	{ glyph: "\uDB83\uDC8E", command: ["bash", "-c", "hyprshot -z -m region --raw --silent | satty --filename -"] },
	{ glyph: "\uF03D", command: ["screen-record"] },
	{ glyph: "\uF074", command: ["bash", "-c", "~/.local/bin/set-random-wallpaper"] },
	{ glyph: "\uDB84\uDEC6", command: ["ghostty", "-e", "bash", "-c", "cd ~/.config/hypr/ && nvim monitors.lua"] }
]

// "volume": { "label": "\uDB81\uDD7E" } -- the speaker glyph next to the slider.
var volumeGlyph = "\uDB81\uDD7E"
// The same slot while the sink is muted: the speaker with an x, the glyph the row
// swaps in. The fill goes grey too, but the glyph is what says why the slider will
// not move the level.
//
// md-volume_mute, U+F075F. This slot used to hold U+F0580, which is
// md-volume_medium -- a speaker with one wave, which reads as "a bit quiet"
// rather than as "muted".
//
// The surrogate pair is easy to get wrong: U+F055F (\uDB81\uDD5F, one hex
// digit off) is md-vector_point, which draws as a cross over a wedge and is
// what this slot silently showed for a while. F075F is \uDB81\uDF5F.
var volumeMutedGlyph = "\uDB81\uDF5F"
// "title": { "text": "Notifications", "button-text": " \uF48E " }
var titleText = "Notifications"
var titleClearGlyph = "\uF48E"

// .widget-buttons-grid { margin: 6px; padding: 6px 2px; border: 1px solid @selected }
// > button { margin: 4px 16px; padding: 6px 12px; font-size: x-large }
// The ten buttons wrap 5 to a row, and `justify-items: space-between` spreads
// them rather than stretching them.
var gridMargin = 6
var gridPaddingH = 2
var gridPaddingV = 6
var gridColumns = 5
var gridButtonPaddingH = 12
var gridButtonPaddingV = 6
// button { margin: 4px 16px }
var gridButtonMarginV = 4
var gridButtonMarginH = 16
// The button's box, measured rather than derived. GTK gives a 16px glyph a
// line box of ~16.6 (ink 13-14 physical px); Qt's is ~21.5 for the same ink, so
// sizing the button from Text metrics made the grid 10px too tall. Sizing it
// from the measurement instead keeps both the glyph *and* the grid right:
// 2 + 12 + 2 * (29 + 8) = 88, against 87.3 measured on a live window.
var gridButtonHeight = 29
var gridFontSize = 16
var gridButtonRadius = 8
// .widget-buttons-grid { border: 1px solid @selected }
var gridBorderWidth = 1

// .widget-volume { padding: 4px; margin: 6px } -- the panel keeps the padding
// and the sides' 6px; the vertical 6px is a centreSectionGap instead.
// scale trough { min-height: 8px } / slider { min-width: 16px; margin: -4px }
var volumeMargin = 6
var volumePadding = 4
var volumeHeight = 16
var sliderSize = 16
var troughHeight = 8
// The ring that says the keyboard is on this knob. The knob is the smallest thing
// the panel's cursor ever lands on -- and it sits inside a trough of the same
// colour family -- so the ring stands off it rather than hugging it, and is drawn
// heavier than any other focus outline in the panel.
//
// 6 rather than 4 because this is the smallest target in the panel: it has to
// read as a ring around the handle rather than as a thicker-edged knob.
var sliderRingGap = 6
var sliderRingBorder = 3
// .widget-volume > box > label { margin-right: 10px }
var volumeLabelGap = 10

// The brightness row beside the volume one. Brightness is otherwise hayami-osd's
// job (the XF86MonBrightness keys), so this row is styled like the volume row
// above it and driven the same way the OSD
// drives the backlight: `brightnessctl -c backlight`, the same class the OSD
// addresses when no --device is given.
//
// The step and the floor are hayami-osd's: 5% of the panel's maximum per press,
// never below 5% (its measured min-brightness, which is 20/400 on this panel).
var brightnessGlyph = "\uDB80\uDCE0"
var sliderStep = 5
var brightnessFloor = 5
// The gap between the two sliders. One pitch apart is the least that lets a
// hovered knob and a focused one show their rings at the same time without the
// two touching: each ring's outer diameter is sliderSize + sliderRingGap * 2.
var volumeRowGap = 12

// The panel's own controls wear the same muted outline a notification card wears,
// so the whole panel reads as one family; when the keyboard is on one of them it
// takes the accent outline a focused card takes, drawn a step heavier. That is the
// grid buttons, the box drawn around them, and the media box.
//
// The boxes are outlined whether or not the keyboard is in them: the grid's box is
// the container the buttons sit in, so it carries the section's outline and follows
// the keyboard's presence in the section rather than one button's focus.
//
// A grid button needs a border of its own rather than a highlight over the
// section, because a highlight inside a grid of ten buttons says nothing about
// which one the keys are aimed at.
var controlBorderWidth = 1
var focusBorderWidth = 2

// How long a transport button stays lit after it fires. A press leaves no other
// trace -- next/previous only move the title the player owns, and play/pause
// only swaps the icon -- so the button answers the key itself.
var transportFlash = 170

// .widget-mpris { border: 1px solid @selected; border-radius: 8px; padding: 8px;
//                 margin: 20px 6px }
// .widget-mpris-player { border-radius: 8px; padding: 6px 14px; margin: 6px }
// "mpris": { "image-size": 96, "image-radius": 12 }
//
// The sides are 6px. The vertical 20px is not: it was the widest
// gap in the panel by a distance no other section had, so it is a
// centreSectionGap like every other section boundary.
var mprisMargin = 6
var mprisPadding = 8
var mprisRadius = 8
var mprisPlayerPaddingH = 14
var mprisPlayerPaddingV = 6
var mprisPlayerMargin = 6
var mprisImageSize = 96
var mprisImageRadius = 12
// .widget-mpris > box > button { border-radius: 8px }, a 1rem-ish square.
var mprisControlSize = 24
// The text column beside the artwork; the panel is 380 wide inside its border,
// minus this widget's padding and the artwork.
var mprisTextWidth = 168

// The transport icons, named so the same symbolic icons out of the theme are
// drawn.
var mprisPrevious = "media-skip-backward-symbolic"
var mprisPlay = "media-playback-start-symbolic"
var mprisPause = "media-playback-pause-symbolic"
var mprisNext = "media-skip-forward-symbolic"

// .widget-title { font-size: 1.2em; font-weight: 600; margin: 6px }
// button { background: @background-alt; border-radius: 8px; padding: 4px 16px }
//
// The 1.2em is relative, and the system font (JetBrainsMono) renders the same
// nominal size both wider and heavier than the scale suggests -- the label
// measured 124px where 86 was wanted -- so the heading sits
// two points under the old size, and a step below semibold: 500 is the family's
// Medium, where 600 picks SemiBold.
var titleSize = 15
var titleWeight = 500
var titleMargin = 6
// The heading's own air above and below. It used to separate the heading from
// the DND row underneath it; the switch lives in this row now, so this is the
// heading's breathing room alone -- and, with centerListTopGap, what sets the
// distance from the heading down to the first card. Kept small because every
// point here comes straight out of the notification list's height.
var titleMarginVertical = 4
// The panel drops the empty spacer a widget stack would put at its head: it made
// the inset from the card's top to the buttons 42 where the
// sides use 20. Without it the buttons get the same air on every side, because
// the card's padding and the grid's own margin already add up to the sides'.
// Horizontal only: the button's height is set beside the switch (see
// titleButtonHeight), not by padding, so there is no vertical padding to set --
// the glyph just centres in the track.
var titleButtonPaddingH = 16
// The clear-all button shares the row's right end with the DND switch, and at
// the switch's own 20px it read as the smaller of the two: the switch's fill is
// the accent whenever notifications are on, while the button's is a 25% tint, so
// the brighter control of the same height wins the eye. 24 -- the switch's track
// plus a step of its own 2px padding -- gives the button the extra it needs to
// stand as its equal. Only the two rings are taller than what they wrap, and the
// button's is the taller of them (24 + 2 * (focusBorderWidth + 1) = 30 against the
// switch's 26), so that ring is what the row now measures.
var titleButtonHeight = 24
// The clear-all button stands beside the switch, and a square button next to a
// pill reads as a stray glyph. The width is fixed rather than derived from the
// height: taking the button up to 24px is about how tall it reads next to the
// switch, and carrying the width along with it would have stretched it 12px
// further into the row. 60 keeps the footprint it has always had -- 2.5:1
// against the 3:1 the height would give it, both clear of square.
var titleButtonWidth = 60
// The DND switch sits immediately left of the clear-all button, so the row's
// right end is a pair of controls rather than one. The switch's focus ring
// stands 3px off it (focusBorderWidth + 1), which is the least this can be
// without the ring touching the button beside it.
var titleControlGap = 8

// The notification list inside the panel. central_control.css lays its cards out
// differently from the popups (see NotifCard): background-alt-ish borders,
// margin 4px 0, padding 4px, and .notification-group { margin: 2px 6px }.
var groupMargin = 2
var groupSideMargin = 6

// Extra air above the list, on top of the group's own 2px margin: the title row
// would otherwise run straight into the first card (or group heading), which
// reads as one block rather than as a heading followed by a list.
var centerListTopGap = 10

// The space between the panel's sections: buttons, volume/brightness, media,
// notifications. One token for all of them, rather than leaving each boundary to
// the two sections' own margins, which made three different distances for the
// same job.
// One token for all of them instead, so every boundary reads the same.
//
// 16 rather than the 12 the buttons and the volume row arrived at: at 12 the
// sections still read as one long stack, and the panel has the room -- the
// notification list takes the height back.
//
// This is the space between sections. The spacing *inside* the notification
// section -- heading to the first card -- is its own, tuned separately.
var centerSectionGap = 16

// .notification-group-headers { font-size: 1.25rem; font-weight: bold;
//                            letter-spacing: 2px }
//
// In caps this was much the heaviest text in the panel -- past even the cards'
// own bold summary. Matched to
// the rest of the shell instead: the same system font, mixed case, no letter
// spacing, a step under the cards' summary and 500, the family's real Medium.
var groupHeaderSize = 13
var groupHeaderWeight = 500
// The gap between the heading and the chevron beside it.
var groupToggleGap = 6
var groupCloseSize = 22
// The chevron that expands and collapses the group, in the same header row and
// the same 22px box as the close-all button at the far end of it. Pointing down
// while collapsed says "there is more under here"; up while expanded says the
// reverse.
var groupToggleIcon = "pan-down-symbolic"
var groupToggleIconOpen = "pan-up-symbolic"
var groupToggleIconSize = 16

// A group of notifications is collapsed by default, and three tracked
// notifications measured as exactly
// one card's worth of height in its panel. Only the newest card is drawn; the
// older ones are the edges of a stack behind it, each one stepping out further
// *below* it: the newest card on top, the older ones under it, which is also the
// order an expanded group lists them in.
//
// How far each edge sits below the one in front of it...
var pileStep = 7
// ...and how much further in from the sides, so the stack fans out as it goes
// back rather than showing as a single thick top edge.
var pileInset = 5
// Deeper stacks draw the same edges: a third sliver is not distinguishable
// from the second, and every edge costs the list a step of height.
var pileMaxEdges = 2

// The vertical space between rows of the list.
//
// central_control.css gives every card `margin: 4px 0px` and every group
// `margin: 2px 6px`, and GTK margins do not collapse, so neighbouring cards sit
// 8 apart and neighbouring groups 4. A card's own top margin applies under a
// group heading too, which is what keeps the heading off the card below it.
var centerCardGap = 8
var centerGroupGap = 4
var groupHeaderGap = 4

// .widget-dnd { font-size: 1.2rem; margin: 6px }
// > switch { border-radius: 8px; padding: 2px } / slider { border-radius: 8px }
//
// A 44-wide switch next to a label reads as the heaviest thing in
// the panel. The slider height falls out of the width (half, less the padding),
// so one number scales the whole control: 36 gives a 16px knob in a 36x20 track.
//
// The switch is the panel's notifications on/off -- the knob sits at the "on"
// end while notifications are shown and slides to "off" when DND silences them,
// which is why the states below are written as notifications-shown rather than
// dnd. Nothing is drawn inside the track: the knob's side and the track's fill
// say which state it is in on their own.
var dndSwitchWidth = 36
var dndSwitchPadding = 2

// The list's empty state, filling the list's area: an icon over a line of text,
// both dimmed, roughly where the first card would sit. A message bubble when
// there is simply nothing to show; the struck-through bell when DND is what is
// keeping the list empty. Both codepoints come from the font's own name tables
// (post + cmap) and were then rendered to read the shapes; guessing at them
// once landed on md-binoculars and md-bio.
var emptyBubbleGlyph = "\uDB80\uDF61"   // U+F0361  md-message
var emptyDndGlyph = "\uDB80\uDC9B"      // U+F009B  md-bell_off
var emptyIconSize = 40
var emptyTextSize = 14
var emptyTextGap = 12
var emptyText = "No notifications"
var emptyDndText = "Do not disturb"
var emptyDndSubText = "Notifications are silenced"

// ── the keyboard cursor ──────────────────────────────────────────────────

// The cursor on a notification is an outline rather than the launcher's bar down
// the left edge: a card is two lines tall, so a bar the height of the text read
// as a border and one the height of the card read as a selection box. The whole
// card's border takes the panel's accent colour instead, which is also what
// distinguishes the cursor from hover -- hover is a background tint.
//
// How much of the list to leave above and below a row that is scrolled to.
var focusScrollMargin = 10

// ── dragging a popup away ───────────────────────────────────────────────

// A popup is dismissed by pulling it sideways past a threshold and letting go.
// The threshold is a share of the card's own width,
// which is also how far the card fades out by -- so it is always fully faded
// before the layer surface it lives in gets a chance to clip it.
var dragDismissFraction = 0.25
var dragMinDistance = 56
// The gap between launches when several cards fly out in a row (delete-all,
// an expanded group's close button): each flight overlaps the previous one a
// little, which is what makes the cascade read as one sweep.
// Card-by-card cascade: the pause between one card's swipe exit and the
// next card's launch, long enough that each flight is seen on its own.
var dismissCascadeStagger = 140
// Margin added to a sweep's model-pin window: one flight (200ms) plus the
// overshoot, so the pin always outlives the last card's exit.
var dismissFlightPad = 400
// How far past the edge it travels once released.
var dragExitOvershoot = 48

// The width of the layer surface the popups live on, over and above the cards.
//
// The surface is anchored to the screen's right edge and the card is flush with
// its *left* edge (a card is popupWidth - popupRowRight wide), so there was no
// travel at all on that side: pulling a popup left clipped it against the edge
// of the surface a pixel in, which read as the card being chopped off rather
// than dragged. This much extra surface on the left is more than the fade needs
// -- the dismiss distance is 94 on a 376-wide card -- and the strip is masked
// out of the input region below, so it swallows nothing.
var popupDragRoom = 132
