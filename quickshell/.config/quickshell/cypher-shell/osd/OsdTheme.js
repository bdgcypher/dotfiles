.pragma library

// Design tokens for the on-screen display, taken from swayosd (which this
// replaced, and which has since been removed) so the new OSD draws the same box
// in the same place as the old one.
//
// Two sources, and they are not the same thing:
//
//   * geometry comes from the live swayosd window, read back with
//     `hyprctl layers -j` while the OSD was up (its layer surface reports the
//     real size, which is more trustworthy than a reading of its CSS);
//   * colours and type come from swayosd's style.css.
//
// The placeholders where swayosd's CSS leaves a value to GTK (the trough, the
// label metrics) were sampled out of a grim capture of the running OSD, which is
// why those numbers look arbitrary -- they are measurements, not choices.

// ── where it goes ────────────────────────────────────────────────────────────

// swayosd-server's --top-margin, and the window is placed so its *bottom* edge
// lands there: measured bottom at 835 on a 982-tall screen = 0.850.
var topMargin = 0.85

// swayosd draws on the overlay layer, so the OSD covers fullscreen windows and
// anything else on screen. The top bar stays on Top, below this.
var layer = "overlay"

// ── box ──────────────────────────────────────────────────────────────────────

// Measured sizes, in logical pixels. swayosd's window is content-sized and its
// height depends only on which parts are present:
//
//   icon + anything .......  68   (32px icon box + 18px padding either side)
//   text and/or bar .......  58   (22px label line + 18px padding)
//   bar only .............  42   (6px bar + 18px padding)
//
// so the padding is a flat 18 and the content decides the rest. A 250px minimum
// holds the window still when the content is a single glyph -- swayosd ships the
// same value as its width-request.
// The paddings are derived from where the content *lands*, not guessed, and they
// are asymmetric: on a 292-wide window the icon's box starts 17 in and the label
// ends 21 from the right. Both halves were checked against swayosd's own box
// (the icon's ink is centred at x33, and 17 + 32/2 is 33).
//
// They stay separate instead of being averaged because the bar and the label are
// positioned by what comes before them -- the whole row has to start at 17 for
// the bar's ink to land on 63.6, which is where swayosd's does.
var paddingLeft = 17
var paddingRight = 21
var paddingY = 18
var minWidth = 250
var minHeight = 42

var radius = 8
var borderWidth = 2
// style.css: window { border: 2px solid #444444 } -- literal, not a pywal colour
var borderColor = "#444444"
// style.css: window { opacity: 0.97 }
var opacity = 0.97

// ── content ──────────────────────────────────────────────────────────────────

// style.css: label { font-family: 'JetBrainsMono Nerd Font'; font-size: 16px }
var fontFamily = "JetBrainsMono Nerd Font"
var labelSize = 16

// The icon box is 32: that is what makes the OSD 68 tall (32 + 18 + 18).
//
// The artwork is drawn at the full 32 rather than inset in the box. swayosd's
// icon *box* is 32 and the theme's speaker SVG only fills ~56% x 62% of its own
// canvas, so the ink lands at ~18 x 20 -- which is what was measured on screen
// (17.5 x 19.5 across the ink, centred at x33). Drawing it smaller to "match" the
// ink would have shrunk the picture instead.
var iconBox = 32
var iconSize = 32
// The gap from the icon's box to the bar. 17 + 32 + 14 = 63, the bar's own x.
var iconGap = 14

// The gap between the bar and the label's box.
var barGap = 24

// Measured from the volume OSD: the bar's ink runs 149 x ~7 logical px.
var barWidth = 149
var barHeight = 7
var barRadius = 3.5

// The progress fill is color6 (style.css: progress { background-color: @progress }
// with @progress: @color6), and the trough is the unstyled GTK default, which
// samples as the foreground at ~38% over the bar's backdrop.
var fillColorIndex = 6
var troughAlpha = 0.34

// ── timing ───────────────────────────────────────────────────────────────────

// Measured: the window is mapped for 1.03s from the trigger. swayosd does not
// fade, it just maps and unmaps, so there is no animation here either.
var duration = 1000
