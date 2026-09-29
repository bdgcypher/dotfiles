import QtQuick
import Quickshell
import Quickshell.Io
import "modules/Theme.js" as Theme

// Where the bar is and what it is showing, and the drag that moves it.
//
// One object, instantiated once in shell.qml and handed to every bar (and to the
// drag preview), because the bar is the same bar on every monitor: an edge or a
// hidden module applies to all of them at once, and a drag on one monitor's bar
// is a change to that one setting.
//
// ── the state file ──────────────────────────────────────────────────────────
//
//   $XDG_STATE_HOME/hayami-shell/bar.json   {"position": "top", "hidden": []}
//
// State, not config: this is what this machine's bar currently looks like, and
// the file is created by the first change rather than shipped in the repo, so a
// fresh stow has no opinion about it and the defaults below apply. The same
// divide the launcher's emoji tone uses.
//
// ── the drag ────────────────────────────────────────────────────────────────
//
// The bar's own background is the drag handle (see Bar.qml): a press on the gap
// between module groups starts a drag, and the release lands the bar on the edge
// the pointer is nearest. The pointer is read from Hyprland rather than from the
// press's own coordinates, because the drag only means anything once the pointer
// has left the bar -- the bar is 26px tall, so "which edge is nearest" is a
// question about the screen, not about the surface -- and a layer surface's
// pointer events are bounded by its own geometry. `hyprctl cursorpos` reports
// the layout position of the pointer, in the same coordinate space as the
// monitor layout below, so the whole calculation stays in one space.
//
// A single long-lived process streams the position while the drag is live (a
// fresh `hyprctl` per frame would be a process a frame); it is killed with the
// drag, so an idle shell runs nothing.
Item {
	id: root

	visible: false
	width: 0
	height: 0

	// ── where it lives ───────────────────────────────────────────────────────

	readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
		|| (Quickshell.env("HOME") + "/.local/state")) + "/hayami-shell/bar.json"

	readonly property var edges: ["top", "bottom", "left", "right"]

	// ── the state ────────────────────────────────────────────────────────────

	// The bar's default edge, which is where it has always been.
	property string position: "top"

	// The strip the bar reserves follows it. Hyprland's `general:gaps_out` is what
	// keeps the bar's edge clear -- see hypr/looknfeel.lua, which computes the
	// same numbers at config load -- and it is applied here too so a move takes
	// effect at once rather than at the next reload. `eval` rather than
	// `keyword`, which this Lua config does not accept; the function it calls is
	// the one defined in looknfeel.lua, so both paths share one definition of the
	// numbers instead of each carrying its own.
	//
	// On every change, not at startup: the config has just reserved the saved
	// edge, and applying the default before the state file has been read would
	// pull the reservation back to the top for an instant.
	//
	// Deferred by a tick, because the edge is passed in the Process's own command
	// and a binding that depends on the value being changed is re-read *after* the
	// change is signalled: starting it directly from here sends the edge the bar
	// has just left, which lands the reservation one move behind.
	onPositionChanged: Qt.callLater(root.applyReserve)

	function applyReserve() {
		reserveProc.running = true
	}

	// Module keys the user has switched off, as a map rather than a list so a
	// lookup is a lookup. Only the keys named here are hidden; anything else --
	// including a module added later -- shows.
	property var hidden: ({})

	// The switchable modules, gathered into the three sets the launcher offers as
	// clusters. The names are the ones Bar.qml passes to `moduleShown`.
	readonly property var clusters: ({
		"status": ["tray", "bluetooth", "network", "vpn", "volume", "memory", "cpu", "battery", "notifications"],
		"time": ["clock", "updates"],
		"layout": ["menu", "workspaces", "layout", "tiling"]
	})

	function shown(key) {
		return hidden[key] !== true
	}

	function isEdge(name) {
		return edges.indexOf(name) >= 0
	}

	// ── the drag ─────────────────────────────────────────────────────────────

	property bool dragging: false
	// The edge the pointer is nearest while dragging, and the monitor it is on,
	// both recomputed on every sample. The preview reads them; nothing else does
	// until the release.
	property string target: ""
	property string monitor: ""

	// The monitor layout, read from Hyprland when a drag starts: `x`/`y` are the
	// layout position, and `width`/`height` are the panel's *physical* pixels, so
	// the logical size the bar's own geometry is measured in is those over the
	// scale (`Quickshell.screens` reports the same logical size).
	property var monitors: []

	property real pressX: -1
	property real pressY: -1
	property real lastX: -1
	property real lastY: -1

	// How far the pointer has travelled from where it went down. A press that
	// never really moves is a click on the bar's background, which does nothing.
	readonly property real travel: (pressX < 0 || lastX < 0)
		? 0
		: Math.max(Math.abs(lastX - pressX), Math.abs(lastY - pressY))

	function beginDrag() {
		if (dragging)
			return

		// Fresh layout per drag: monitors come and go, and a drag is the one
		// moment the layout is load-bearing.
		if (!layoutProc.running) {
			layoutProc.collected = ""
			layoutProc.running = true
		}

		pressX = -1
		pressY = -1
		lastX = -1
		lastY = -1
		monitor = ""
		target = ""
		dragging = true
	}

	// Forgetting the press as well as the drag: `travel` is read out of these, and
	// a finished drag that left them set would report the last drag's distance for
	// as long as the shell ran.
	function forgetPointer() {
		pressX = -1
		pressY = -1
		lastX = -1
		lastY = -1
	}

	function cancelDrag() {
		dragging = false
		monitor = ""
		target = ""
		forgetPointer()
	}

	function endDrag() {
		if (!dragging)
			return ""

		var moved = travel >= Theme.dragThreshold
		var landed = target
		dragging = false
		monitor = ""
		target = ""
		forgetPointer()

		if (moved && landed !== "" && landed !== position)
			return setPosition(landed)
		return position
	}

	// One `hyprctl cursorpos` sample, as JSON.
	function sample(raw) {
		if (!dragging)
			return

		var point
		try {
			point = JSON.parse(raw)
		} catch (e) {
			return
		}
		if (!point || typeof point.x !== "number" || typeof point.y !== "number")
			return

		if (pressX < 0) {
			pressX = point.x
			pressY = point.y
		}
		lastX = point.x
		lastY = point.y

		var mon = monitorAt(point.x, point.y)
		monitor = mon ? mon.name : ""
		target = mon ? nearestEdge(mon, point.x, point.y) : ""
	}

	function monitorAt(x, y) {
		for (var i = 0; i < monitors.length; i++) {
			var m = monitors[i]
			if (x >= m.x && x < m.x + m.width && y >= m.y && y < m.y + m.height)
				return m
		}
		return null
	}

	// How far the pointer is from one edge of a monitor, on the monitor's own
	// logical coordinates.
	function edgeDistance(edge, m, x, y) {
		if (edge === "bottom")
			return m.y + m.height - y
		if (edge === "left")
			return x - m.x
		if (edge === "right")
			return m.x + m.width - x
		return y - m.y
	}

	// The nearest of the four edges, which is what makes the whole gesture
	// symmetric: the pointer only has to cross the halfway line to the edge it
	// wants, whichever edge it started from.
	//
	// With hysteresis: the edge already chosen is kept until another is nearer by
	// `Theme.dragHysteresis`. Near the middle of the screen two edges are equally
	// near, and the pointer's own jitter is then enough to change the answer
	// several times a second -- the preview blinks between two edges and the drop
	// is whichever one the last sample happened to land on. The first sample of a
	// drag has no previous choice to keep (`target` is empty), so it picks the
	// nearest edge outright and everything after it has to mean a change.
	function nearestEdge(m, x, y) {
		var dTop = y - m.y
		var dBottom = m.y + m.height - y
		var dLeft = x - m.x
		var dRight = m.x + m.width - x

		var best = "top"
		var bestD = dTop
		if (dBottom < bestD) {
			best = "bottom"
			bestD = dBottom
		}
		if (dLeft < bestD) {
			best = "left"
			bestD = dLeft
		}
		if (dRight < bestD) {
			best = "right"
			bestD = dRight
		}

		if (best !== target && isEdge(target)
				&& edgeDistance(target, m, x, y) - bestD < Theme.dragHysteresis)
			return target
		return best
	}

	function loadMonitors(raw) {
		var list
		try {
			list = JSON.parse(raw)
		} catch (e) {
			return
		}
		if (!list || !list.length)
			return

		var out = []
		for (var i = 0; i < list.length; i++) {
			var m = list[i]
			var scale = m.scale && m.scale > 0 ? m.scale : 1
			out.push({
				name: m.name,
				x: m.x,
				y: m.y,
				width: Math.round(m.width / scale),
				height: Math.round(m.height / scale)
			})
		}
		monitors = out
	}

	// ── changing it ──────────────────────────────────────────────────────────

	function setPosition(edge) {
		if (!isEdge(edge) || edge === position)
			return position
		position = edge
		save()
		return position
	}

	// The map edit on its own, so a cluster of nine modules is one write rather
	// than nine: the file is written by whatever the user asked for, not by each
	// module inside it.
	function applyShown(key, on) {
		if (key === "")
			return false
		if (shown(key) === on)
			return on

		// Every other hidden key is kept and this one is dropped, then put back if
		// this call is the one hiding it -- one rule for both directions, so
		// showing a hidden module cannot leave it hidden.
		var map = {}
		for (var k in hidden) {
			if (hidden[k] === true && k !== key)
				map[k] = true
		}
		if (!on)
			map[key] = true
		hidden = map
		return on
	}

	function setShown(key, on) {
		if (key === "" || shown(key) === on)
			return shown(key)
		var result = applyShown(key, on)
		save()
		return result
	}

	function toggle(key) {
		return setShown(key, !shown(key)) ? "shown" : "hidden"
	}

	// A whole cluster at once. Both directions are expressed, so the launcher can
	// offer "hide the status cluster" and "show it again" as plainly as it offers
	// the modules themselves; the result is the same map either way.
	function setCluster(name, on) {
		var keys = clusters[name]
		if (!keys)
			return "unknown"
		for (var i = 0; i < keys.length; i++)
			applyShown(keys[i], on)
		save()
		return on ? "shown" : "hidden"
	}

	function showAll() {
		if (Object.keys(hidden).length === 0)
			return "shown"
		hidden = ({})
		save()
		return "shown"
	}

	// ── the clock's calendar ─────────────────────────────────────────────────
	//
	// Three preferences, saved here rather than in a file of their own because
	// they are the same kind of thing as the edge and the hidden modules: what
	// this machine's shell looks like. All three are the user's to change from
	// the panel itself -- the "W" heading toggles the week start, and the year
	// rail's double-tap asks for the pair below -- and none of them has a
	// default worth shipping in the repo, so the defaults are the absence of a
	// value.

	// Which day the week starts on, by name ("monday"), or "" to follow the
	// locale's own first day. By name rather than by index: the file is meant to
	// be readable, and the name is what the heading's tooltip promises to set.
	property string calendarWeekStart: ""

	// A birth year, or 0 for "not set" -- which is also what the panel's own
	// parser makes of a blank, malformed, future or implausibly distant one. The
	// life rail stays hidden until there is one.
	property int calendarBirthYear: 0

	// The span the life rail measures against. A round number rather than
	// anything from a table: the point is the reminder, not the arithmetic.
	property int calendarLifeExpectancy: 90

	function setCalendarWeekStart(name) {
		if (name === calendarWeekStart)
			return name
		calendarWeekStart = name
		save()
		return name
	}

	function setCalendarLife(birthYear, expectancy) {
		calendarBirthYear = birthYear
		calendarLifeExpectancy = expectancy
		save()
		return String(birthYear)
	}

	// ── persistence ──────────────────────────────────────────────────────────

	FileView {
		id: stateFile

		path: root.statePath
		watchChanges: true
		onFileChanged: reload()
		onLoaded: root.load(text())
		onTextChanged: root.load(text())
	}

	// One `hyprctl eval` per move, on an edge that has already been validated by
	// `setPosition` (or read back out of the state file), passed as its own
	// argument rather than through a shell.
	Process {
		id: reserveProc

		command: ["hyprctl", "eval", "hayami_bar_gaps(\"" + root.position + "\")"]

		// The function this calls is defined in hypr/looknfeel.lua, so a machine
		// whose Hyprland has not reloaded since it pulled that file fails here
		// (hyprctl exits 7 on a Lua error). Better said out loud than a bar that
		// moves while the screen's edge stays reserved where it was.
		// The exit status arrives as a formal parameter rather than by the old
		// name-injection into the handler's scope, which QML deprecates (and says
		// so in the log on every start).
		onExited: function(exitCode) {
			if (exitCode !== 0)
				console.warn("hayami-shell: could not move the reserved space -- run `hyprctl reload` to pick up hypr/looknfeel.lua")
		}
	}

	Process {
		id: stateWriter

		property string payload: "{}"

		command: ["bash", "-c", "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\"",
			"bar-state", payload, root.statePath]
	}

	function load(raw) {
		if (!raw)
			return

		var data
		try {
			data = JSON.parse(raw)
		} catch (e) {
			console.warn("hayami-shell: could not parse the bar state: " + e)
			return
		}

		if (isEdge(data.position))
			position = data.position

		var map = {}
		var list = data.hidden || []
		for (var i = 0; i < list.length; i++) {
			if (typeof list[i] === "string" && list[i] !== "")
				map[list[i]] = true
		}
		hidden = map

		// The calendar's three, each taken only when it is the shape it is
		// supposed to be: a state file edited by hand should cost the panel the
		// value it could not read, not the whole panel.
		var calendar = data.calendar || {}
		calendarWeekStart = typeof calendar.weekStartDay === "string"
			? calendar.weekStartDay : ""
		var birth = Number(calendar.birthYear)
		calendarBirthYear = isFinite(birth) && birth > 0 ? Math.round(birth) : 0
		var span = Number(calendar.lifeExpectancy)
		calendarLifeExpectancy = isFinite(span) && span > 0 ? Math.round(span) : 90
	}

	function save() {
		var keys = []
		for (var k in hidden) {
			if (hidden[k] === true)
				keys.push(k)
		}
		keys.sort()

		stateWriter.payload = JSON.stringify({
			position: position,
			hidden: keys,
			calendar: {
				weekStartDay: calendarWeekStart,
				birthYear: calendarBirthYear,
				lifeExpectancy: calendarLifeExpectancy
			}
		})
		stateWriter.running = true
	}

	// ── the keyboard ─────────────────────────────────────────────────────────
	//
	// Whether the bar is being driven from the keyboard: `hayami-bar keyboard`
	// sets this over the same IPC socket its other verbs use, and the bar's own
	// keybind toggles it.
	//
	// A transient flag, never written to bar.json. It describes what the keyboard
	// is doing rather than what the bar looks like, and the keyboard is the one
	// thing a shell restarted mid-navigation must give back: a bar that came up
	// still holding it would leave every window unable to type.
	//
	// It is one flag for every monitor's bar, and the bars decide between
	// themselves which one answers -- the one on the focused monitor, so exactly
	// one surface asks the compositor for the keys. See Bar.qml.
	property bool keyboardMode: false

	function setKeyboardMode(on) {
		keyboardMode = on
		return on ? "on" : "off"
	}

	function toggleKeyboardMode() {
		return setKeyboardMode(!keyboardMode)
	}

	// ── reading the pointer while dragging ───────────────────────────────────

	// One process rather than one per frame: the loop below samples at ~30Hz and
	// dies with the drag. `tr` folds hyprctl's pretty-printed JSON onto one line,
	// which is what lets the parser take it a sample at a time.
	Process {
		id: cursorStream

		running: root.dragging
		command: ["bash", "-c", "while :; do hyprctl -j cursorpos 2>/dev/null | tr -d '\\n '; echo; sleep 0.03; done"]

		stdout: SplitParser {
			onRead: function(line) { root.sample(line) }
		}
	}

	Process {
		id: layoutProc

		property string collected: ""

		command: ["hyprctl", "-j", "monitors"]

		stdout: SplitParser {
			onRead: function(line) { layoutProc.collected += line + "\n" }
		}

		onExited: root.loadMonitors(layoutProc.collected)
	}

	// ── IPC ──────────────────────────────────────────────────────────────────
	//
	// What hayami-bar speaks to. The verbs are named for what they do to the
	// state rather than for what the CLI's flags are called, so `edge` is the
	// setting and `position` is the CLI's name for it.

	IpcHandler {
		target: "bar"

		function edge(name: string): string {
			return root.setPosition(name)
		}

		function toggle(key: string): string {
			return root.toggle(key)
		}

		function reveal(key: string): string {
			return root.setShown(key, true) ? "shown" : "hidden"
		}

		function conceal(key: string): string {
			return root.setShown(key, false) ? "shown" : "hidden"
		}

		function cluster(name: string, on: string): string {
			return root.setCluster(name, on === "1" || on === "true")
		}

		function revealAll(): string {
			return root.showAll()
		}

		// The pointer, driven by hand. The drag is read from Hyprland rather than
		// from the bar's own pointer events and cannot be fed by synthetic input
		// (a warped cursor generates no motion), so a script -- or a check on a
		// running shell -- can drive the drag's geometry this way. Same reason the
		// launcher exposes filter() and pick().
		function pointer(x: string, y: string): string {
			if (!root.dragging)
				root.beginDrag()
			root.sample(JSON.stringify({ x: Number(x), y: Number(y) }))
			return root.stateJson()
		}

		function drop(): string {
			return root.endDrag()
		}

		// Bar keyboard mode, for the keybind and for hayami-bar. `on` is "on" or
		// "off" the way hayami-bar spells them, or "toggle" for the key that has
		// to work both ways. Both spellings of true are taken -- the digits were
		// the only ones this read at first, so "on" fell through to off.
		function keyboard(on: string): string {
			if (on === "toggle")
				return root.toggleKeyboardMode()
			return root.setKeyboardMode(on === "1" || on === "true" || on === "on")
		}

		function state(): string {
			return root.stateJson()
		}
	}

	function stateJson() {
		var keys = []
		for (var k in hidden) {
			if (hidden[k] === true)
				keys.push(k)
		}
		keys.sort()

		return JSON.stringify({
			"position": position,
			"hidden": keys,
			"calendar": {
				"weekStartDay": calendarWeekStart,
				"birthYear": calendarBirthYear,
				"lifeExpectancy": calendarLifeExpectancy
			},
			"keyboard": keyboardMode,
			"dragging": dragging,
			"target": target,
			"monitor": monitor,
			"travel": travel,
			"monitors": monitors
		})
	}
}
