pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Theme.js" as Theme

// The dictation glow: a soft accent bloom *inside* the focused window while the
// microphone is open.
//
// ── one band, not four edges ────────────────────────────────────────────────
//
// The band is a single chain of overlapping soft emitters placed at even arc
// length around the window's perimeter; the bottom edge is the stretch of it
// that is drawn, and it is drawn all the way to both ends of the window.
//
// The earlier version drew one gradient per edge, each spanning the window's
// full width or height. Both edges painted the corner square, so the corners
// summed into bright patches and the light read as four panels laid over the
// window rather than as one leak under a bezel. That is a defect of the
// geometry, not of the tuning, so per-edge numbers could never remove it.
//
// Each emitter is a radial feather centred on the frame. Half of it falls
// outside the surface and is clipped away, so what shows inside the window is a
// soft wash reaching inward. Neighbours overlap by well over half their width;
// the sum of that overlap is the band, and the band's inner boundary is
// therefore a continuous curve rather than four straight edges.
//
// ── why it is a wave, not a pulse ───────────────────────────────────────────
//
// Every emitter's reach and strength are sampled from a travelling train of
// crests at its position along the perimeter. The crests are not alike: a
// little over a third of them are half the width of the others, roughly one
// in seven is broad enough to fill most of the gap to its neighbours, and the
// taller a crest is the skinnier it is, so what passes is a train of waves of
// different sizes
// rather than one wave repeating. Their tops are peaks rather than domes, and
// each leans: its apex sits off centre so one flank is longer than the other,
// the way a dune's ridge does, so a crest builds gradually and falls away
// quickly instead of being a symmetrical hump. That is what makes one stand
// clear of the flat between. In silence the whole train is a thin line a dozen-
// odd pixels deep just off the frame, whose peaks and troughs are almost the
// same height: enough to be seen at rest, so the rim says "ready" and nothing
// more, and everything that makes it read as a wave exists only while there is
// a voice in it.
//
// The audio bands ride on that wave: the bass drives the bottom edge, and the
// overall level mixes in over the last stretch at each end, where the slope is.
// Speech pushes the band deeper; the wave alone keeps it moving through silence,
// which is what stops a held vowel from freezing it. (The treble drove the top
// edge, which is not drawn any more, so it is not read here at all.)
//
// ── the bottom edge, and the slope at its two ends ──────────────────────────
//
// Only the bottom edge is lit, all the way to both ends of the window. The chain
// is still walked round the whole perimeter, because the wave is one train
// travelling round it and its crests have to arrive along the bottom at the
// spacing the train gives them; what is built is the bottom stretch, and nothing
// else.
//
// The band is deepest at the window's two edges and slopes down from them into
// the middle, so what ends it is the band thinning out rather than a corner. The
// slope is one curve and it is the only shape in this file: an exponential fall,
// steep where it leaves the border and flattening out as it goes, so the drop is
// spent in the first few tens of pixels and the rest of the run is its shallow
// tail. Nothing is added at the ends: no corner, no rise up the sides, no
// plateau.
//
// It is a level rather than a taper of the wave, so the slope is the same curve
// whatever the train is doing and the train's crests stand out of it as it
// descends. The boundary drawn is the higher of the two, and the max of two
// continuous curves is continuous, so the handover is invisible rather than a
// step.
//
// The slope is scaled by the band like everything else, so it exists only while
// there is a voice in it: in silence it collapses onto the resting line and the
// rim stays even. An end that stood up in silence would be a shape rather than a
// reading.
//
// ── why a surface, and why this surface ─────────────────────────────────────
//
// Hyprland's own border cannot do this: it is 2px of compositor paint, and a
// bloom is not a border colour. So the glow is drawn by the shell, on a layer
// surface above the window, and the compositor rule in
// hypr/apps/dictation.lua lands every geometry change in one frame.
//
// The surface is exactly the window -- not the monitor, and not the window plus
// a margin. A layer surface is the size of its buffer, so a screen-sized
// transparent one is megabytes redrawn around the edges, and, being on top of
// everything, it is what stops a fullscreen window being scanned out directly.
// Matching the frame keeps the buffer to the only area the glow can occupy, and
// it clips the outer halves of the emitters for free.
//
// ── where the window is ─────────────────────────────────────────────────────
//
// Not from Quickshell's Hyprland binding, which is what it should have been:
// on this machine `Hyprland.activeToplevel` stays null and no entry in
// `Hyprland.toplevels` is ever marked activated, even though `hyprctl
// activewindow` names the focused window. Measured by logging the binding
// during a recording, so it is a broken reading rather than a guess. The
// monitor list from the same service does work, which is why the monitor
// lookup below still uses it.
//
// So the focused window is read from `hyprctl -j activewindow` whenever
// dictation is live. That is also fresher than the binding would have been:
// Hyprland sends no event when a window is moved, so a cached IPC object goes
// stale, while this query cannot. It runs only between the microphone opening
// and closing, at 4Hz, because the window can change focus or move
// mid-dictation.
//
// `at` and `size` are layout coordinates and `at` is *global*, so the monitor's
// origin is subtracted before drawing on this monitor's surface. They describe
// the client area, which is where the light starts: the 2px compositor border
// is outside it and stays unlit, like a bezel.
//
// ── when it is not drawn ────────────────────────────────────────────────────
//
// A fullscreen window (values 2 and 3) is left alone: a bloom over a game or a
// film is a decoration on something deliberately immersive, and it is also
// exactly when direct scanout matters. Maximised (1) still glows -- that is a
// window in a layout, not a takeover.
//
// The shell's own panels suppress it too. They are layer surfaces just above
// this one, and while one is open the focused *window* is still the window
// behind it, so without the gate the bloom would be painted over a card that is
// covering it. The launcher is passed in rather than reached for, because its
// open flag lives on the launcher itself -- the same split the agent panel uses.
PanelWindow {
	id: root

	required property var modelData

	// Shared by every surface in the shell; never a colour of its own.
	property var pal: null

	// The shell's one dictation reading. `listening`, `level`, `bass` and
	// `treble` all come from here, so the glow and the bar's glyph cannot
	// disagree about whether the microphone is open.
	property var dictation: null

	// Named `bar`, not `barState`: the shell passes this as `bar: barState`,
	// and a property called barState assigned from an id of the same name reads
	// itself -- the delegate's own property wins the name lookup, so it stayed
	// null and the panel gate below never fired. Measured, not guessed.
	property var bar: null
	property var notifications: null
	property bool launcherOpen: false

	screen: modelData

	// The window border's own colour: colour6. That is what the pywal template
	// writes into the hypr palette (colors-hyprland.lua sets `border_active`
	// from it), and therefore what `general:col.active_border` is painted in.
	// The glow is a continuation of that border rather than an accent of its
	// own, so a wallpaper re-tints both together and they cannot drift apart.
	readonly property color tint: (pal && pal.colors && pal.colors.length > 6)
		? pal.colors[6] : (pal ? pal.accent : "#CEA56A")

	// ── the focused window ───────────────────────────────────────────────────

	// The last `hyprctl -j activewindow` object, or null when there is no
	// focused window (the desktop, a layer surface, a locked screen).
	property var raw: null

	// The microphone is open, so the window the glow is drawn around needs
	// following. This is also what starts and stops the query below.
	readonly property bool tracking: dictation !== null && dictation.listening

	Process {
		id: reader

		command: ["hyprctl", "-j", "activewindow"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: root.readWindow(text)
		}
	}

	// 4Hz while listening. Hyprland has no event for a move or a resize, and
	// the focus can change mid-dictation, so the query is repeated for as long
	// as the microphone is open -- and only then. A window moved by a drag can
	// therefore trail the light by up to a quarter second, which is the price
	// of not polling the compositor all day for a decoration that is only
	// drawn for a few seconds at a time.
	Timer {
		id: poll

		interval: 250
		repeat: true
		running: root.tracking

		onTriggered: if (!reader.running)
			reader.running = true
	}

	function readWindow(text) {
		var data = null
		try {
			data = JSON.parse(text)
		} catch (e) {
			return
		}
		root.raw = data && data.address ? data : null
	}

	// Start reading at once rather than up to a poll interval later, and drop
	// the reading on the way out so the surface collapses even if the next
	// recording opens on a different window.
	onTrackingChanged: {
		if (tracking) {
			if (!reader.running)
				reader.running = true
		} else {
			reader.running = false
			raw = null
		}
	}

	readonly property var monitors: Hyprland.monitors.values

	readonly property var winMonitor: {
		if (!raw)
			return null
		for (var i = 0; i < monitors.length; i++) {
			var m = monitors[i]
			if (m.lastIpcObject && m.lastIpcObject.id === raw.monitor)
				return m
		}
		return null
	}

	readonly property var mon: winMonitor ? winMonitor.lastIpcObject : null

	readonly property bool mine: mon !== null && modelData !== null
		&& mon.name === modelData.name

	// The window's client rect on this monitor, in this monitor's logical
	// pixels. `at` is global layout space, so the monitor's origin comes off it.
	readonly property rect frame: {
		if (!raw || !mon || !raw.at || !raw.size)
			return Qt.rect(0, 0, 0, 0)
		return Qt.rect(raw.at[0] - mon.x, raw.at[1] - mon.y,
			raw.size[0], raw.size[1])
	}

	// Hyprland's fullscreen field: 0 none, 1 maximised, 2 fullscreen, 3
	// fullscreen without the bar. Only the last two are a takeover.
	readonly property bool fullscreen: raw !== null
		&& raw.fullscreen !== undefined && raw.fullscreen >= 2

	readonly property bool panelsUp: launcherOpen
		|| (bar && (bar.agentPanel || bar.calendarPanel))
		|| (notifications && notifications.centerOpen)

	readonly property bool engaged: dictation !== null && dictation.listening
		&& frame.width > 0

	visible: engaged && mine && !fullscreen && !panelsUp

	// ── the surface's own rectangle ──────────────────────────────────────────
	//
	// The window itself. The bloom faces inward, so there is nothing to reserve
	// outside the frame, and the surface never reaches the bar or the desktop.
	// The clamp to the monitor is only a guard against a window straddling the
	// output edge mid-move, so the margins can never go negative.
	readonly property rect surfaceRect: {
		var x = Math.max(0, Math.floor(frame.x))
		var y = Math.max(0, Math.floor(frame.y))
		var monitorWidth = modelData ? modelData.width : x + 1
		var monitorHeight = modelData ? modelData.height : y + 1
		var right = Math.max(x + 1,
			Math.min(monitorWidth, Math.ceil(frame.x + frame.width)))
		var bottom = Math.max(y + 1,
			Math.min(monitorHeight, Math.ceil(frame.y + frame.height)))
		return Qt.rect(x, y, right - x, bottom - y)
	}

	// The frame in the surface's coordinates, which is what everything below is
	// drawn from.
	readonly property rect winRect: Qt.rect(frame.x - surfaceRect.x,
		frame.y - surfaceRect.y, frame.width, frame.height)

	anchors.top: true
	anchors.left: true
	margins.top: Math.round(surfaceRect.y)
	margins.left: Math.round(surfaceRect.x)

	implicitWidth: Math.round(surfaceRect.width)
	implicitHeight: Math.round(surfaceRect.height)

	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"

	// Top, not Overlay: it must be above windows, but below the OSD and the
	// notification popups, which are the shell's transient readings.
	WlrLayershell.layer: WlrLayer.Top
	WlrLayershell.namespace: "quickshell:dictation"
	// None: this surface is decoration and must never take the keyboard from the
	// window being dictated into.
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

	// An empty input region: every click goes through the glow to the window
	// underneath it, so the decoration can never eat a press.
	mask: Region {}

	// ── the animation ────────────────────────────────────────────────────────
	//
	// 10fps, not 60: the bloom is slow and diffuse, so the cadence reads as
	// breathing rather than as frames, and every frame is the window-sized
	// surface rendered again. The timer stops with the surface, so an idle shell
	// runs no frame work at all.
	//
	// Ten for a measured reason. The earlier ring was 10% of one core at 30fps
	// and 8% at 20fps; cutting the bars barely moved it, because the cost is this
	// surface being re-rendered, not the items drawn on it. The cadence is the
	// knob that actually moves it.
	//
	// The bands are smoothed here rather than in the state singleton so the
	// singleton stays a reading and the surface owns its animation. 0.28 per
	// frame settles in about four frames -- quick enough to follow a syllable,
	// slow enough not to strobe.
	//
	// One phase, and a wrap that is a whole lap. The travel is one crest per
	// 2pi, so the wrap is two pi times the crest count: every crest back where
	// it started. The swell and the drift in the crest heights would otherwise
	// end a lap mid-turn, which is a step in the wave every few seconds; they
	// run at the nearest fraction of the train's speed that closes on the same
	// lap instead, and the step is divided into a whole number of frames, so
	// the last frame lands on the first. A lap is about 30s, long enough that
	// the repeat is not something you sit and watch for.
	property real phase: 0
	property real smoothLevel: 0
	property real smoothBass: 0

	// What the bloom is made of: the fixed transcription step is dimmer than a
	// live recording, because the microphone is closed and the glow is only
	// saying "still working".
	readonly property real strength: (dictation && dictation.transcribing)
		? Theme.dictationGlowTranscribe : Theme.dictationGlowAlpha

	// ── the emitters ─────────────────────────────────────────────────────────
	//
	// An emitter's radius is wider than the intended reach because a radial
	// feather has spent most of its alpha by the time it reaches its rim: the
	// last third is invisible on a dark window. 1.45x puts the visible feather
	// at roughly the reach the theme names.
	readonly property real dotRadius: Math.max(40,
		Math.round(Theme.dictationGlowReach * 1.45))
	readonly property real dotSize: dotRadius * 2

	// Even spacing, comfortably closer than the emitter's half-width so several
	// of them overlap at any point. Spacing is the band's smoothness: the sum
	// of neighbours is what fills the dips between two centres, and the ripple
	// it leaves runs at the spacing's own period, so this number *is* the
	// fineness of the edge. It has been tightened twice -- 101px still read as
	// a row of discs, 65px as a ripple -- and at 40px the sum is smooth at the
	// scale the eye reads the band, while the crests, four hundred-odd pixels
	// apart, stay the only bumps that matter.
	readonly property real dotSpacing: dotRadius * 0.20

	// Along-edge stretch. 1.55 covered over 600px of the edge, and even 1.0 was
	// as wide as a crest, so the overlap averaged a short wave back into a
	// smooth band. 0.55 keeps each emitter narrower than even a narrow crest:
	// the chain's depth follows the crest instead of smoothing it away. The
	// spacing is unchanged, and the overlapping feathers still keep the band
	// continuous along the edge.
	readonly property real dotStretch: 0.55



	// A radial feather, baked into an SVG data URI. It is a texture rather than
	// a Shape on purpose: on this Qt (6.12) a ShapePath filled with a
	// `RadialGradient` paints nothing at all -- the same circle with a flat
	// fill draws, and changing only the fill to a radial gradient makes it
	// vanish, with no warning in the log. A texture is the form that works.
	//
	// The accent is written *into* the SVG rather than drawn white and tinted
	// afterwards. That keeps the palette the only source of colour, with no
	// second colour to keep in step and no colourisation pass over a
	// window-sized offscreen texture. The stops are the feather's profile: a
	// core that is a little darker than the frame was, then a steep shoulder
	// into a much fainter tail -- the band against the frame reads darker, and
	// the light farther in is more translucent instead of one even gradient.
	// The core is long enough that neighbouring emitters' cores overlap: with a
	// short core, the narrow chain read as a row of beads along the frame.
	readonly property string dotSource: {
		if (!pal)
			return ""
		var colour = String(tint)
		var svg = "<svg xmlns='http://www.w3.org/2000/svg' width='128' height='128'"
			+ " viewBox='0 0 128 128'>"
			+ "<defs><radialGradient id='g'>"
			+ "<stop offset='0' stop-color='" + colour + "' stop-opacity='0.88'/>"
			+ "<stop offset='0.50' stop-color='" + colour + "' stop-opacity='0.78'/>"
			+ "<stop offset='0.64' stop-color='" + colour + "' stop-opacity='0.42'/>"
			+ "<stop offset='0.78' stop-color='" + colour + "' stop-opacity='0.12'/>"
			+ "<stop offset='0.90' stop-color='" + colour + "' stop-opacity='0.03'/>"
			+ "<stop offset='1' stop-color='" + colour + "' stop-opacity='0'/>"
			+ "</radialGradient></defs>"
			+ "<circle cx='64' cy='64' r='64' fill='url(#g)'/>"
			+ "</svg>"
		return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
	}

	// The drawn stretch of the chain. `s` is the position along the perimeter in
	// surface pixels, which is what the wave is sampled by: the perimeter is
	// walked clockwise -- top left to right, down the right edge, along the
	// bottom right to left -- so the bottom's positions are the ones the whole
	// walk gives them and the train arrives along the edge unchanged. `x` is
	// where that puts the emitter on the bottom; the y is the frame's own.
	property var blobs: []

	// The crest train's geometry for the current frame size. The count is an
	// integer on purpose and the span is derived from it, so the last crest meets
	// the first with the spacing of all the others: a fixed wavelength that does
	// not divide the loop leaves one irregular gap per lap, and that gap would
	// land on the corner where the loop closes. Rounding the count instead moves
	// the spacing by a pixel or two, which is invisible next to the widths.
	property real loopLength: 0
	property int crestCount: 1
	property real crestSpan: 405

	// How far in from each end the slope reaches before the band is back at the
	// trough. Short on purpose: the curve is steep at the border and spends itself
	// in the first few tens of pixels, so this is the *extent* of the slope and not
	// its length -- the visible fall is over well before the run ends. The clamp is
	// only for a window too narrow to hold a run at each end; on anything ordinary
	// it is the flat 160.
	readonly property real cornerRun: Math.min(160, winRect.width * 0.45)

	// The fall from the edge, 1 at the border and 0 at the end of the run:
	//
	//     (e^-k u - e^-k) / (1 - e^-k),   u = reach / cornerRun
	//
	// An exponential, so it leaves the border at a steep slope and flattens out as
	// it goes -- the mirror of a ramp, which would land on the trough with a
	// corner, and of the parabola before it, which fell at the border and then lay
	// flat. `k` is set from a half-life of 37px: the fall is halfway down by then,
	// a fifth of the way down at 74px, and all but flat by 148px. Subtracting e^-k
	// and rescaling is what makes the tail land on exactly 0 at `cornerRun`
	// instead of on the 5% the raw exponential still carries, so it joins the
	// trough with no step.
	readonly property real fallK: Math.log(2) * cornerRun / 37

	function fallAt(u) {
		var tail = Math.exp(-fallK)
		return (Math.exp(-fallK * u) - tail) / (1 - tail)
	}

	// How many turns the broad swell makes round the loop. Scaled to the loop so
	// it closes exactly too, rather than pinning a wavelength that then has to
	// break at the seam.
	property int swellTurns: 1

	// The lap: two pi per crest, so one lap is every crest back where it started.
	readonly property real phaseWrap: 2 * Math.PI * crestCount

	// The slow terms' speeds, as the nearest fraction of the train's speed that
	// closes on that lap. A flat 0.6 and 0.2 only return after a whole number of
	// turns when the crest count happens to be a multiple of five, so for most
	// window sizes a lap would end mid-turn and the seam would jump. 0.6 of a
	// crest per lap or 0.58 is not a difference anyone can see; a jump is.
	readonly property real swellRate: Math.round(0.6 * crestCount) / crestCount
	readonly property real driftRate: Math.round(0.2 * crestCount) / crestCount

	// The per-frame step, chosen so a lap is a whole number of frames. At a flat
	// 0.25 the lap is 502.65 frames, so the wrap lands a fraction of a step
	// short and the train steps back about six pixels once every half minute --
	// small, but exactly the seam the wrap exists to avoid. A whole number of
	// steps costs a hundredth of a percent of speed.
	readonly property real frameStep: phaseWrap
		/ Math.max(1, Math.round(phaseWrap / 0.25))

	readonly property string geometryKey: winRect.x + ":"
		+ winRect.y + ":" + winRect.width + ":" + winRect.height

	onGeometryKeyChanged: rebuild()
	Component.onCompleted: rebuild()
	Component.onDestruction: blobs = []

	function rebuild() {
		var w = Math.max(0, winRect.width)
		var h = Math.max(0, winRect.height)
		if (w < 2 || h < 2) {
			blobs = []
			return
		}

		var perimeter = 2 * (w + h)
		loopLength = perimeter
		crestCount = Math.max(5, Math.round(perimeter / 405))
		crestSpan = perimeter / crestCount
		swellTurns = Math.max(1, Math.round(perimeter / 1150))
		// The spacing is the whole perimeter's, so the bottom's share of it is
		// exactly the spacing the bottom had when all four edges were built: the
		// fineness of the band does not change with the window's shape.
		var count = Math.max(16, Math.round(perimeter / dotSpacing))
		var step = perimeter / count
		var out = []

		// The bottom edge, walked exactly as the whole perimeter walks it: every
		// position from `w + h` up to `2w + h`, each halfway between two corners
		// of its step. Written as the walk's own test rather than as a count,
		// because a count rounds the ends off -- `floor(w / step)` dropped the
		// last half step at the left, so the outermost emitter sat fifty pixels in
		// from that border and the band sagged there while the right end, which
		// had its last full step, did not.
		for (var i = 0; ; i++) {
			var s = w + h + (i + 0.5) * step
			if (s >= 2 * w + h)
				break
			out.push({ x: w - (s - w - h), y: h, s: s })
		}

		// One emitter past each end of the window, which the surface clips. The
		// band is the sum of neighbours, and at a border only the inside ones are
		// there to sum, so the last few pixels came out dimmer than the rest of
		// the edge and the glow read as stopping at the window rather than running
		// to it. These two give the border the overlap its neighbours have.
		// The run gets emitters of its own, and they are narrow. The band's are two
		// hundred and twenty pixels wide, and a blob that wide has a flat top across
		// most of its width, so the boundary drawn is the envelope of the tallest
		// blob within a hundred pixels rather than the curve itself -- whatever
		// heights the run is given, it comes out as a shelf, a straight ramp and
		// another shelf. A fifth of that width turns inside twenty pixels, so the
		// curve is what gets drawn; the spacing is fine enough that the tops of
		// neighbouring emitters overlap into one line.
		//
		// `s` carries on the walk's parameter along the bottom, so a crest keeps the
		// phase it would have had.
		var fine = Math.max(4, Math.round(step / 8))
		var runStretch = dotStretch * 0.18
		for (var k = fine; k < cornerRun; k += fine) {
			out.push({ x: k, y: h, s: 2 * w + h - k, sx: runStretch })
			out.push({ x: w - k, y: h, s: w + h + k, sx: runStretch })
		}

		// One emitter just past each border, which the surface clips. The band is
		// the sum of its neighbours, and at a border only the inside ones are there
		// to sum, so without these the last pixels come out dimmer than the rest of
		// the edge. They sit half a *run* step out rather than half a walk step,
		// because a narrow blob twenty pixels out ends before the border and leaves
		// it dark; their depth is the border's own, since they stand in for the
		// overlap the border is missing.
		out.push({ x: w + 0.5 * fine, y: h, s: w + h - 0.5 * fine,
			reach: 0, sx: runStretch })
		out.push({ x: -0.5 * fine, y: h, s: 2 * w + h + 0.5 * fine,
			reach: 0, sx: runStretch })

		blobs = out
	}

	// How much of the reading an emitter answers to. The middle of the bottom
	// edge is pure bass; over the last stretch at each end the overall level
	// mixes in, so the slope swells with the voice as well as with the bass. The
	// weight is proximity to the end, tapering off over roughly the feather's
	// reach -- the same taper the four-edge version used along the bottom.
	function bandAt(x) {
		var taper = dotRadius * 1.35
		var end = Math.max(0, 1 - Math.min(x, winRect.width - x) / taper)
		return (smoothBass + end * smoothLevel) / (1 + end)
	}

	// One pass per frame over the emitters. Positions are fixed until the
	// window moves; only the transform and the opacity animate. The texture is
	// the same for all of them and never changes, so this is a handful of
	// property writes rather than any geometry work.
	// A stable pseudo-random number in [0,1) for an index. Stable is the point:
	// a crest keeps its width and height for the whole loop, so the next lap is
	// the same train of shapes rather than a new one.
	function hash01(n) {
		var v = Math.sin(n * 127.1 + 311.7) * 43758.5453
		return v - Math.floor(v)
	}

	function paint() {
		var count = blobs.length
		if (count < 1 || loopLength < 1 || crestSpan < 1)
			return

		// Where the train is this frame, wrapped into the loop. One crest passes
		// per 2pi of phase, which is the speed the wave has always had. The sign
		// is negative: the train runs counter-clockwise, against the direction the
		// perimeter is walked in, which along the bottom edge is left to right. The
		// wrap below handles the negative value because it uses floor, so the train
		// still lands in [0, loopLength) with no seam.
		var travel = -(phase / (2 * Math.PI)) * crestSpan
		travel = travel - Math.floor(travel / loopLength) * loopLength

		// The crests, in a table for this frame: where each one is, how wide it
		// is and how tall. Every one of them moves every frame, so the table is
		// rebuilt rather than moved -- it is about twenty entries, cheaper than
		// two hundred emitters doing the lookup arithmetic themselves.
		//
		// Width and height come from the crest's *identity*, its index, rather
		// than from where it is, so they travel with it: what passes is a fixed
		// sequence of shapes, not a pattern flickering in place. There are three
		// sizes. A little over a third are narrow, at a little over half a wide
		// one's width, and the narrow ones are the tall ones: a crest's height is
		// read off its width, so the skinniest is the tallest and the broad one is
		// the shortest. That is what makes a crest read as a peak rather than as a
		// rounded hump, because the rise is concentrated where the wave is narrow.
		// About one in seven is broad, most of the way to its neighbours either
		// side, and low, so it reads as a swell that swallows the troughs around it
		// rather than as a wall. The rest are the ordinary width. The heights also
		// drift on a slow oscillator, so the train does not come back identical a
		// lap later.
		var centres = []
		var halves = []
		var heights = []
		for (var n = 0; n < crestCount; n++) {
			var pick = hash01(n * 1.7 + 0.3)
			// Widths are factors of the spacing, so every crest stays inside its
			// own gap. They are the crest's *footprint*, the point where its skirt
			// reaches zero, not its half-maximum width: the bump below is sharp
			// enough that half its height sits at about 0.70 of the footprint, so
			// the narrow crest measures roughly a hundred pixels across and the
			// ordinary one about a hundred and eighty-five.
			//
			// The broad one is counted off rather than hashed. With about twenty
			// crests in a lap a hash threshold put two of them side by side and
			// then none for the rest of it, and two broad crests in a row fuse
			// into one long plateau instead of reading as two waves. A fixed
			// stride cannot do that, and the offset keeps the first one off the
			// seam.
			var broad = n % 7 === 3
			var narrow = !broad && pick < 0.50
			var width = broad ? 0.95 : (narrow ? 0.36 : 0.66)
			// Height follows width, the other way round: the skinniest crest is the
			// tallest and the broad one is the shortest, so the wave comes to its
			// sharpest points where it rises highest. A crest still has its own
			// jitter and the slow drift, so two of a size are not identical -- but
			// both are smaller than the gap between the sizes, so they cannot make a
			// wide crest taller than a narrow one. A narrow crest is about a third
			// taller than a wide one and twice a broad one.
			var height = 0.98 - 0.44 * (width - 0.36) / 0.59
			var centre = n * crestSpan + travel
			centres.push(centre - Math.floor(centre / loopLength) * loopLength)
			halves.push(crestSpan * width)
			heights.push(height
				* (0.86 + 0.14 * hash01(n * 3.1 + 41.7))
				* (0.90 + 0.10 * Math.sin(phase * driftRate + n * 2.1)))
		}

		for (var i = 0; i < count; i++) {
			var dot = dots.itemAt(i)
			if (!dot)
				continue
			var d = blobs[i]
			var band = bandAt(d.x)

			// The crest field here: the sum of the crests whose skirts reach this
			// point, at most three, since even the broadest crest stops short of
			// the next centre. The bump is a Lorentzian peak inside a squared
			// window. The window takes it to zero at its own rim with zero slope,
			// so neighbours meet in a rounded trough rather than a kink and a
			// trough stays genuinely low; the Lorentzian half is what puts a point
			// on the top, because its shoulders are long and steep where a
			// cosine's are round. That is what lets the silent rim be almost flat
			// while a peak still stands clear of it.
			//
			// A cosine cannot be sharpened by raising it to a power: every power
			// of a cosine is a Gaussian near its peak, so squaring it and cubing
			// it differ by a few per cent across the top and neither reads as a
			// peak. That was the first attempt here and it measured as no change.
			var nearest = Math.floor((d.s - travel) / crestSpan)
			var crest = 0
			for (var k = nearest - 1; k <= nearest + 1; k++) {
				var idx = ((k % crestCount) + crestCount) % crestCount
				var ds = d.s - centres[idx]
				if (ds > loopLength * 0.5)
					ds -= loopLength
				else if (ds < -loopLength * 0.5)
					ds += loopLength
				var half = halves[idx]
				if (Math.abs(ds) >= half)
					continue
					// A dune rather than a hump. The bump is read through a skewed
				// coordinate, so its apex sits off centre and the flank on one side
				// is longer than the other: a crest builds gradually and falls away
				// quickly, with its ridge leaning the way the wave travels. The map is
				// monotone and takes the rim to itself, so the footprint, the zero
				// slope at the rim and the overlap with the neighbours are unchanged.
				var u = ds / half
				var x = u + 0.30 * (1 - u * u)
				var skirt = 1 - x * x
				// 0.30 is the Lorentzian's half-height radius as a fraction of the
				// footprint: the smaller it is the more the bump is a spike on a
				// base rather than a wave, so it stays above a quarter.
				var r = x / 0.30
				crest += heights[idx] * skirt * skirt / Math.sqrt(1 + r * r)
			}
			crest = Math.min(1, crest)

			// A broad swell under the train, so the rim is never a perfect ring
			// even between crests.
			var swell = Math.sin(2 * Math.PI * d.s / loopLength * swellTurns
				+ phase * swellRate + 2.1)

			// Resting depth is a thin line, and it has to be a line you can
			// actually see. It used to be a sliver a few pixels deep, which on a
			// still window read as no glow at all -- the rim only became visible
			// once you spoke, so the shell looked like it had failed to start.
			// The floor below is set so the edge is drawn at rest, and the wave's
			// own modulation is kept to a small fraction of it, so peaks and
			// troughs still come out nearly the same height with nothing in the
			// microphone. Everything that makes it a wave is multiplied by the
			// band, and so exists only while you speak -- which is what makes
			// talking unmistakable rather than a slightly bigger version of
			// quiet. The alpha base keeps the accent a colour rather than a grey
			// haze, and the feather's flat core keeps the light against the frame
			// more opaque than the wash behind it. Both the reach and the alpha
			// floors are raised relative to where the speaking level sits, so the
			// two ends of the band's range stay as far apart as they were.
			var trough = 0.085 + 0.012 * crest + 0.006 * swell
			var wave = trough + band * (0.05 + 0.60 * crest)

			// ── the slope at each end ────────────────────────────────────────
			//
			// The band is deepest at the window's two edges and slopes down from
			// them into the middle, so what ends it is the band thinning out
			// rather than a corner. `pool` is the depth at the edge, set a little
			// past the tallest crest so the ends read as deeper than the wave
			// rather than as one more crest of it; `reach` is how far in the
			// emitter sits, over the run. The shape is the one curve in this file,
			// `fallAt`: steep at the border, flattening out, and landing on the
			// wave exactly at the end of the run.
			//
			// The boundary drawn is the higher of the slope and the wave, so a
			// crest coming along stands out of the slope as it descends instead
			// of being cut off by it.
			// The slope is drawn by the run's narrow emitters only. A band emitter
			// carries the slope just as well in depth, but its top is two hundred
			// pixels wide and flat, so the boundary would be the envelope of the
			// tall ones -- which is the shelf and ramp the shape came out as, no
			// matter what heights it was given. Left with the wave, the band emitter
			// still draws a crest standing out of the slope, which is the union's
			// point; the slope itself is the narrow line's to draw.
			var depth = wave
			var shape = crest
			var lift = 1
			var reach = d.reach !== undefined ? d.reach
				: Math.min(d.x, winRect.width - d.x)
			if (d.sx !== undefined && reach < cornerRun) {
				// The fall is a *lift above the wave*, not a level of its own: it is
				// the edge's depth at the border, where `fallAt` is 1 and the wave
				// cancels out, and it is the wave itself at the end of the run, where
				// `fallAt` is 0. A level measured against the trough instead spends its
				// tail below the crests, where the wave draws over it and the curve
				// cannot be seen; a level measured against the crests arrives at the
				// crest's height but at the slope's brightness, and stood a third of
				// the edge proud of the band it was meant to land on. Landing on the
				// wave leaves nothing to mismatch: height and `shape` both go to the
				// wave's own, so the join is invisible and the crests show through it.
				var pool = trough + band * 0.95
				lift = fallAt(reach / cornerRun)
				var slope = wave + (pool - wave) * lift
				if (slope > depth) {
					depth = slope
					// Both the height and the brightness follow the lift rather than the
					// depth. Taken from the depth, the brightness sat at its brightest
					// for as long as the lift held the boundary above the crests and then
					// dropped to the wave's own at the very end, which drew as a darker
					// line across the band exactly where the curve stopped. Blending from
					// a full crest at the border to the wave's own shape at the end
					// leaves nothing for a step to sit on.
					shape = crest + (1 - crest) * lift
				}
			}

			var alpha = strength * 0.55
				* (0.60 + 0.40 * Math.min(1, shape * 1.4) * band)
				* (0.50 + 0.65 * band)
				* (0.86 + 0.14 * Math.min(1, shape * 1.6))

			// The run's emitters sit five pixels apart, several times the overlap
			// the band's own spacing gives, so their light adds up on top of the
			// band's wherever they are. At the band's opacity that made the run's
			// body brighter than the band beyond it, and the difference stopped at
			// a soft vertical edge -- the line that could be seen where the curve
			// ended. Tying the extra light to the lift means it is full at the
			// border and gone at the end of the run, so the opacity meets the band
			// instead of stopping at it.
			//
			// Its square root rather than the lift itself: the lift's own decay is
			// steep enough that the last third of the run carried almost no light
			// of its own, and the curve there was just the band -- it met the wave
			// long before the run was over. Holding the light up while still taking
			// it to nothing at the end keeps the tail and leaves no edge to see.
			if (d.sx !== undefined)
				alpha *= Math.sqrt(lift)

			// The stretch and the depth are the two axes of the one feather: the
			// long one runs along the edge, the other reaches inward from it.
			// Every emitter built is on the bottom edge, so that is a stretch
			// across the window and a depth up it.
			dot.opacity = alpha
			dot.sx = d.sx !== undefined ? d.sx : dotStretch
			dot.sy = depth
		}
	}

	Timer {
		id: ticker

		interval: Theme.dictationGlowFrameMs
		repeat: true
		running: root.visible

		onTriggered: {
				root.phase = (root.phase + root.frameStep) % root.phaseWrap
				root.smoothLevel += ((root.dictation ? root.dictation.level : 0) - root.smoothLevel) * 0.18
				root.smoothBass += ((root.dictation ? root.dictation.bass : 0) - root.smoothBass) * 0.18
				root.paint()
			}
	}

	// The next recording starts from silence and from the first crest, rather
	// than from the amplitude and phase the last one ended on.
	onVisibleChanged: {
		if (!visible) {
			smoothLevel = 0
			smoothBass = 0
			phase = 0
		}
	}

	// ── the band ─────────────────────────────────────────────────────────────
	//
	// One emitter. The texture is a square feather; the item is placed so its
	// centre sits on the frame, which is why only the inner half is ever seen.
	// The depth and the stretch live in the transform, so no frame touches the
	// image itself.
	Repeater {
		id: dots

		model: root.blobs

		delegate: Image {
			id: dot

			required property var modelData

			width: root.dotSize
			height: root.dotSize
			x: root.winRect.x + modelData.x - root.dotRadius
			y: root.winRect.y + modelData.y - root.dotRadius
			opacity: 0

			source: root.dotSource
			// The feather has no detail, so a 128px master is ample even when
			// stretched across the window; rasterising it per item at 128
			// keeps the texture small and the scaling smooth.
			sourceSize.width: 128
			sourceSize.height: 128
			smooth: true

			property real sx: 1
			property real sy: 1

			transform: Scale {
				origin.x: root.dotRadius
				origin.y: root.dotRadius
				xScale: dot.sx
				yScale: dot.sy
			}
		}
	}
}
