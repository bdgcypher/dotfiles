.pragma library

// Geometry and type metrics for the launcher box.
//
// Two sources, both deliberate:
//
//   * Values marked "measured" were taken from walker on this machine by
//     capturing it on an empty workspace and diffing against the bare desktop,
//     so they are walker's real rendered box, not its CSS.
//   * The rest come from walker's own themes/default/style.css and layout.xml,
//     which is where the padding/border/item rhythm lives.
//
// The point of this file is that "looks like walker" is expressed as numbers in
// one place, so tuning it later does not mean hunting through the layout.

// ── window / box ─────────────────────────────────────────────────────────────

// measured: walker centres the box and ignores anything smaller than ~304 wide.
var minBoxWidth = 304;
var defaultBoxWidth = 780;   // layout.xml width-request
var boxHeight = 572;         // measured (layout.xml asks for 570)
var keybindsHeight = 658;    // measured; the keybinds list is content-driven

// style.css: .box-wrapper
var boxPadding = 20;
var boxBorder = 2;
var boxRadius = 8;
var boxBgAlpha = 0.95;

// layout.xml: the outer Box is a GtkBox with spacing: 10, and GTK separates
// visible children by exactly that -- so the search row, the content and the
// keybind bar each sit 10px apart. It applies only to visible children, which is
// why the gap disappears when an edge element is hidden.
var boxSpacing = 10;

// ── search row ───────────────────────────────────────────────────────────────

// style.css: .search-container
var searchPadding = 10;
var searchBorderBottom = 1;

// ── list ─────────────────────────────────────────────────────────────────────

// style.css: .item-box { padding: 4px 14px }, .item-text-box { padding: 14px 0 },
// .item-image { margin-right: 14px }, .large-icons { -gtk-icon-size: 18px }
var itemPadV = 4;
var itemPadH = 14;

// A focused or hovered list row gets a bar down its left edge, in the same
// colour as its text. The tint alone was a subtle cue to spot when scanning a
// list, and this is the one part of the row that does not move with the text.
//
// The emoji grid does not use it: a cell already shows focus with its background
// highlight, and between two glyphs the bar read as a stray mark.
var focusBar = 2;
var itemTextPadV = 14;
var itemIconMargin = 14;
var itemIconSize = 18;

// layout.xml: the default theme pins the list to 260 and lets the preview take
// the rest; the keybinds theme lets the list expand instead.
var listWidth = 260;
var listMaxHeight = 400;         // default theme
var keybindsListMaxHeight = 500; // keybinds theme

// A row is text padding + one line + item padding, which is how walker gets its
// roomy rows; used for the scroll maths.
var lineHeight = 18;
var rowHeight = itemTextPadV * 2 + lineHeight + itemPadV * 2; // 54

// The focus bar is a line of text tall, not a whole row tall: 54px of accent
// beside a single 14px line read heavy. The line box is what the glyphs occupy,
// descenders included, and the bar is centred on the row like the text is.
//
// Declared here rather than beside focusBar above: a `var` that reads a later
// declaration in this file is simply undefined, which is what made the bar
// disappear when it was declared up there.
var focusBarHeight = lineHeight;

// ── hint bar ─────────────────────────────────────────────────────────────────

// style.css: .keybind-hints { padding: 10px; margin-top: 10px; border-top: 1px solid @color6 }
var hintsPadding = 10;
var hintsBorderTop = 1;

// layout.xml: #Keybinds carries margin-top: 10 on top of the Box's 10px spacing,
// so the gap above the hint bar is 20 rather than 10.
var hintsMarginTop = 10;

// walker prints its hints from the binary and I could not read them back
// (no OCR here, and the strings are not in the binary in plain form), so these
// are the equivalent labels for the keys this launcher actually binds. One
// place to change once you tell me walker's exact wording.
var hints = [
	{ key: "enter", label: "run" },
	{ key: "esc", label: "close" },
	{ key: "\u2191\u2193", label: "navigate" }
];

// The emoji picker's hints, and only two of them.
//
// The tone swatches sit at the right end of the same bar, and the box is 400
// wide, so the hints have ~215px to live in. Measured against the real rendered
// text (8.4px per character at 14px) a third hint does not fit: "enter copy" +
// "esc close" + "tab category" is 285px, which ran into the swatches -- the
// hint text ended at x1077 where the swatch band starts at x1018. Two hints end
// well clear of them. Tab-to-switch-category and ctrl+t for the tone are not
// advertised because they cannot be; the tab strip and the swatches are both
// visible and clickable, so the picker is still discoverable without them.
var emojiHints = [
	{ key: "enter", label: "copy" },
	{ key: "esc", label: "close" }
];

function hintsFor(emojiMode) {
	return emojiMode ? emojiHints : hints;
}

// ── emoji picker ─────────────────────────────────────────────────────────────

// The picker is a grid, so it is sized in whole columns across the box's inner
// width instead of the list's fixed 260: 400 wide leaves 39.5px per cell at 9
// columns, which fits a 20px glyph with room for the highlight around it.
var emojiColumns = 9;
var emojiCellHeight = 34;
var emojiCellSize = 30;      // the rounded highlight behind the glyph
var emojiCellRadius = 6;
var emojiSize = 20;          // the glyph itself
var emojiHighlightAlpha = 0.22;
var emojiHeaderHeight = 26;
var emojiHeaderSize = 12;
var emojiTabHeight = 34;
var emojiTabIconSize = 20;    // matches the grid's glyph size
var emojiTabRule = 2;
// An inactive tab is dimmed, not faded out: at 0.45 the monochrome icons
// disappeared into the background entirely.
var emojiTabInactiveOpacity = 0.6;
var emojiSwatchSize = 16;
var emojiSwatchSpacing = 6;
// The swatch is a rounded square, not a circle: a round control next to the
// square tone glyphs looked like two different things stacked.
var emojiSwatchRadius = 3;

// The five tone fills, light to dark, sampled from the glyphs Noto Color Emoji
// draws for U+1F3FB..U+1F3FF (centre of each swatch, in the picker's own swatch
// row). The picker fills the swatch with these instead of setting the tone
// glyph: the glyph comes out with near-hard corners and a hair wider than its
// box, so it read as a square sitting inside a rounded ring. Drawing the fill
// lets it share the ring's radius, which is what makes the two match.
var emojiToneFills = ["#fadbb6", "#ddb790", "#b58967", "#a06740", "#6d5047"];

// The neutral swatch is the yellow an unmodified emoji is drawn in, sampled the
// same way: it is the modal colour of the tone-less glyphs (the waving hand and
// the whole smileys page both come out #fcc828). It used to be an empty ring,
// which read as a swatch that had failed to load rather than as "no tone".
var emojiToneDefault = "#fcc828";

// Negative is the neutral default, 0..4 the five modifiers.
function emojiToneFill(tone) {
	if (tone < 0)
		return emojiToneDefault
	return tone < emojiToneFills.length ? emojiToneFills[tone] : "transparent"
}

// Emoji get their own family rather than the box's font with fallback: naming
// the colour font directly is what keeps a ZWJ sequence (a flag, a profession)
// from being drawn as its separate parts.
var emojiFontFamily = "Noto Color Emoji";

// ── type ─────────────────────────────────────────────────────────────────────

// style.css: font-family: "JetBrainsMono NF", ...; font-size: 14px
// (the bar uses 12px, walker 14px -- this is walker's box)
var fontFamily = "JetBrainsMono Nerd Font"
var fontSize = 14;

// Placeholder text is dimmed: .input placeholder { opacity: 0.5 }
var placeholderOpacity = 0.5;

// Placed inside the box
var previewPadding = 10;
var previewBorder = 1;

function boxWidthFor(argWidth) {
	var w = parseInt(argWidth, 10);
	if (isNaN(w) || w <= 0)
		return defaultBoxWidth;
	return Math.max(w, minBoxWidth);
}

function boxHeightFor(theme) {
	return theme === "keybinds" ? keybindsHeight : boxHeight;
}

function listMaxHeightFor(theme) {
	return theme === "keybinds" ? keybindsListMaxHeight : listMaxHeight;
}

function visibleRows(theme) {
	return Math.max(1, Math.floor(listMaxHeightFor(theme) / rowHeight));
}
