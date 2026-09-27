import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Query.js" as Query
import "Metrics.js" as Metrics
import "Providers.js" as Providers
import "EmojiData.js" as EmojiData

// The launcher: walker's replacement.
//
// walker draws a centred box inside a full-screen layer surface, so this is a
// full-screen overlay too -- the box is Box.qml. Modes, prefixes, ordering and
// the menu tree itself all come from the elephant TOMLs, converted to JSON by
// scripts/menus-json.py, so both launchers show the same content while walker is
// still installed.
//
// It answers on the "launcher" IPC target; bin/.local/bin/cypher-menu is what
// the keybinds and scripts call.

PanelWindow {
	id: root

	property var palette

	// ── launcher state ───────────────────────────────────────────────────────

	property bool open: false
	property string mode: ""

	// The picker replaces the whole list rather than adding to it, so it gets a
	// property instead of a check spread through the file.
	readonly property bool emojiMode: mode === "emoji"
	property string theme: "default"
	property string widthArg: ""
	property string placeholderArg: ""
	property bool showSearch: true
	property bool showHints: true
	property string query: ""

	property var items: []
	property var results: []
	property int selected: 0

	// dmenu (-d): the caller gets one line back through a FIFO.
	property bool dmenuMode: false
	property string dmenuFifo: ""
	property bool dmenuIndex: false

	// elephant.toml: terminal_cmd = "ghostty -e"
	readonly property string terminalCmd: "ghostty -e"

	// ── data ─────────────────────────────────────────────────────────────────

	readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
	readonly property string clipboardPath: (Quickshell.env("XDG_STATE_HOME")
		|| (Quickshell.env("HOME") + "/.local/state")) + "/cypher-shell/clipboard.jsonl"
	readonly property string emojiStatePath: (Quickshell.env("XDG_STATE_HOME")
		|| (Quickshell.env("HOME") + "/.local/state")) + "/cypher-shell/emoji.json"
	property var menuData: ({})

	// Desktop entries are cached rather than read per keystroke: the model fills
	// in asynchronously after the shell starts.
	property var apps: []

	// Static list generated once per session (Scripts).
	property var runnerList: []

	// The emoji picker. `emojiData` is the vendored dataset, `emojiItems` its
	// entries, and the rest is the picker's own state: which category tab is
	// active, the chosen skin tone, and how often each emoji has been picked.
	property var emojiData: ({ groups: [], tones: [], emoji: [] })
	property var emojiItems: []
	property var emojiRows: []
	property int emojiGroupIndex: -1
	property int emojiTone: -1
	property var emojiUsage: ({})
	property bool emojiSearching: false

	// Clipboard history, appended by the wl-paste watcher.
	property var clipboardHistory: []

	// Items for the providers produced by a helper process (files, calc).
	property var dynamicItems: []

	Connections {
		target: DesktopEntries.applications

		function onValuesChanged() {
			root.refreshApps()
		}
	}

	// .desktop Icon= is normally a theme name, but may be an absolute path.
	function appIconPath(icon) {
		if (!icon)
			return ""
		if (icon.charAt(0) === "/")
			return icon
		// `check` is not optional here. Without it Quickshell returns the
		// image://icon URL for any name, and a name it cannot load renders as a
		// magenta "no icon" placeholder rather than nothing (it warns "Could not
		// load icon ... from request" and still hands back an image, so the
		// Image's own error guard never sees a failure). With it, a name the
		// theme cannot produce is dropped and the row simply has no icon: right
		// for the ~16 entries whose Icon= is not in the theme (Avahi's
		// network-wired, printer, hwloc, ...).
		return Quickshell.iconPath(icon, true)
	}

	// Alphabetic, case-insensitive. localeCompare is deliberately not used: the
	// QML JS engine's support for its options argument is not guaranteed, and a
	// throw here would empty the app list.
	function compareNames(a, b) {
		var x = a.toLowerCase()
		var y = b.toLowerCase()
		return x < y ? -1 : (x > y ? 1 : 0)
	}

	function refreshApps() {
		var out = []
		var values = DesktopEntries.applications.values || []
		for (var i = 0; i < values.length; i++) {
			var e = values[i]
			// A couple of entries ship no Icon= at all (Wiremix, jellyfin-tui)
			// and no installed theme carries a name for them. Rather than invent
			// artwork, use the entry's own shape: a terminal app with nothing to
			// draw gets the terminal icon, which every theme has.
			var iconPath = root.appIconPath(e.icon)
			if (iconPath === "" && e.runInTerminal)
				iconPath = root.appIconPath("utilities-terminal")

			out.push({
				text: e.name,
				/* Searched fields, in penalty order -- elephant's toSearch list when
				   only_search_title is off, which this config has on, so the app is
				   found by its name alone. That is why typing "fire" no longer
				   drags in every Firefox-based PWA (`Web app (firefox)` lives in
				   the comment). subtext and keywords stay for display purposes but
				   are deliberately not searched. */
				fields: [e.name],
				// elephant's desktopapplications.toml: MinScore 30, and apps are the
				// one provider that keeps a score equal to it (`>=` everywhere else
				// is `>`).
				minScore: 30,
				minScoreInclusive: true,
				subtext: e.genericName || e.comment || "",
				// The pane would only restate the name as the entry's long
				// comment, so an app carries no preview at all ("" means no
				// pane).
				preview: "",
				keywords: (e.keywords || []).join(" "),
				// The glyph font holds no icons, so the entry's icon is resolved
				// through the icon theme and drawn as an image (rowThumb).
				icon: "",
				iconPath: iconPath,
				weight: 0,
				kind: "app",
				app: e
			})
		}
		// Browsing the app list shows every entry at once, so it is kept in name
		// order rather than DesktopEntries' own.
		out.sort(function(a, b) { return root.compareNames(a.text, b.text) })
		root.apps = out
	}

	// ── generated provider lists ──────────────────────────────────────
	//
	// Scripts and emoji come from scripts/providers-json.py, generated once per
	// session and read from the runtime dir. --refresh regenerates them.

	FileView {
		id: providersFile

		path: root.runtimeDir + "/quickshell-cypher-shell-providers.json"
		onLoaded: root.loadProviderData(text())
		onTextChanged: root.loadProviderData(text())
	}

	Process {
		id: providersGen

		command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/cypher-shell/scripts/providers-json.py", "--quiet"]
		onExited: providersFile.reload()
	}

	// ── clipboard history ────────────────────────────────────────────
	//
	// The watcher keeps the history current while the shell runs -- the same job
	// elephant does for walker. Being a child of the shell ties it to the shell's
	// lifetime.

	FileView {
		id: clipboardFile

		path: root.clipboardPath
		watchChanges: true
		onFileChanged: reload()
		onLoaded: root.loadClipboard(text())
		onTextChanged: root.loadClipboard(text())
	}

	Process {
		id: clipboardWatcher

		running: true
		// Single instance: the watcher outlives the shell (nothing reaps it when
		// the shell is restarted), so a lock keeps a second one from piling up on
		// every restart. Whichever holds the lock keeps the history current.
		command: ["bash", "-c", "exec flock -n " + root.runtimeDir + "/cypher-shell-clipboard.lock wl-paste --watch python3 " + Quickshell.env("HOME") + "/.config/quickshell/cypher-shell/scripts/clipboard-watch.py"]
	}

	// ── process-backed providers (files, calc) ───────────────────────

	Process {
		id: filesProc

		property string collected: ""
		command: []

		stdout: SplitParser {
			onRead: function(line) { filesProc.collected += line }
		}

		onExited: root.loadFileList(filesProc.collected)
	}

	Process {
		id: calcProc

		property string collected: ""
		command: []

		stdout: SplitParser {
			onRead: function(line) { calcProc.collected += line + "\n" }
		}

		onExited: root.loadCalcResult(calcProc.collected)
	}

	// One debounce for both, so typing does not spawn a process per keystroke.
	Timer {
		id: dynamicTimer

		property string target: ""
		interval: 160
		repeat: false

		onTriggered: root.runDynamic()
	}

	// ── provider data ────────────────────────────────────────────

	function loadProviderData(raw) {
		if (!raw)
			return
		try {
			var data = JSON.parse(raw)
			root.runnerList = data.runner || []
		} catch (e) {
			console.warn("launcher: could not parse the provider cache: " + e)
		}
	}

	// The picker's dataset is vendored in the package rather than generated into
	// the runtime cache: it is static content, and the list's ":" provider reads
	// the same entries, so names and shortcodes cannot drift apart.
	FileView {
		id: emojiFile

		path: Quickshell.env("HOME") + "/.config/quickshell/cypher-shell/data/emoji/emojis.json"
		onLoaded: root.loadEmojiData(text())
		onTextChanged: root.loadEmojiData(text())
	}

	function loadEmojiData(raw) {
		if (!raw)
			return
		try {
			var data = JSON.parse(raw)
			root.emojiData = data
			root.emojiItems = data.emoji || []
		} catch (e) {
			console.warn("launcher: could not parse the emoji data: " + e)
			return
		}
		if (root.mode === "emoji")
		root.rebuild()
	}

	// Tone and usage persist between sessions; the file is small and only the
	// picker touches it.
	FileView {
		id: emojiStateFile

		path: root.emojiStatePath
		watchChanges: true
		onFileChanged: reload()
		onLoaded: root.loadEmojiState(text())
	}

	Process {
		id: emojiStateWriter

		property string payload: "{}"
		command: ["bash", "-c", "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\"",
			"emoji-state", payload, root.emojiStatePath]
	}

	function loadEmojiState(raw) {
		if (!raw)
			return
		try {
			var data = JSON.parse(raw)
			root.emojiUsage = data.usage || {}
			root.emojiTone = typeof data.tone === "number" ? data.tone : -1
		} catch (e) {
			console.warn("launcher: could not parse the emoji state: " + e)
		}
	}

	function saveEmojiState() {
		emojiStateWriter.payload = JSON.stringify({ tone: root.emojiTone, usage: root.emojiUsage })
		emojiStateWriter.running = true
	}

	function loadClipboard(raw) {
		var out = []
		var lines = String(raw || "").split("\n")
		for (var i = 0; i < lines.length; i++) {
			var line = lines[i].trim()
			if (line === "")
				continue
			try {
				out.push(JSON.parse(line))
			} catch (e) {
				continue
			}
		}
		root.clipboardHistory = out
	}

	function loadFileList(raw) {
		try {
			root.dynamicItems = Providers.fileItems(JSON.parse(raw))
		} catch (e) {
			console.warn("launcher: could not read the directory listing: " + e)
			root.dynamicItems = []
		}
		dynamicResults()
	}

	function loadCalcResult(raw) {
		// qalc echoes the expression before the answer, so take the last line that
		// actually has something on it.
		var result = ""
		var lines = String(raw || "").split("\n")
		for (var i = lines.length - 1; i >= 0; i--) {
			if (lines[i].trim() !== "") {
				result = lines[i].trim()
				break
			}
		}
		root.dynamicItems = Providers.calcItems(root.queryText(), result)
		dynamicResults()
	}

	// Process-backed results are shown as produced: a partial path or expression
	// is not something the fuzzy ranker should reorder.
	function dynamicResults() {
		results = dynamicItems
		selected = results.length > 0 ? 0 : -1
	}

	function runDynamic() {
		if (dynamicTimer.target === "files") {
			filesProc.collected = ""
			filesProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/cypher-shell/scripts/list-dir.py", queryText()]
			filesProc.running = true
			return
		}

		if (dynamicTimer.target !== "calc")
			return

		var expr = queryText().trim()
		if (expr === "") {
			dynamicItems = []
			dynamicResults()
			return
		}
		calcProc.collected = ""
		calcProc.command = ["qalc", "-t", expr]
		calcProc.running = true
	}

	function menuNames() {
		var menus = menuData && menuData.menus ? menuData.menus : {}
		var names = []
		for (var key in menus)
			names.push(key)
		return names.sort()
	}

	// ── menu tree from the elephant TOMLs ────────────────────────────────────────

	FileView {
		id: menuFile

		path: root.runtimeDir + "/quickshell-cypher-shell-menus.json"
		watchChanges: true

		onFileChanged: reload()
		onLoaded: root.loadMenus(text())
		onTextChanged: root.loadMenus(text())
	}

	Process {
		id: menuGen

		// First run of a session has no cache yet; generate it, then reload.
		command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/cypher-shell/scripts/menus-json.py", "--quiet"]
		onExited: menuFile.reload()
	}

	function loadMenus(raw) {
		if (!raw)
			return
		try {
			root.menuData = JSON.parse(raw)
		} catch (e) {
			console.warn("launcher: could not parse the menu cache: " + e)
		}
	}

	Component.onCompleted: {
		refreshApps()
		if (!menuFile.loaded)
			menuGen.running = true
		if (!providersFile.loaded)
			providersGen.running = true
	}

	// ── providers ────────────────────────────────────────────────────────────

	function providerNames() {
		// walker's rules: -m pins one provider, a "/" "." ":" "=" "@" "$" prefix
		// pins its own, and otherwise the set depends on whether anything has
		// been typed yet -- the main menu while empty, all of it once you type.
		if (dmenuMode)
			return ["dmenu"]
		return Query.providerSetFor(mode, query)
	}

	// `withPath` labels an entry with the menu it came from, which is what tells
	// two entries with the same name apart once the search reaches the nested
	// menus: "Screen Recording" reads as Utilities → Capture.
	//
	// The path is carried as `path`, not `subtext`: `subtext` belongs to the
	// preview pane, and the narrow boxes have no preview pane to put it in (SUPER
	// opens the main menu at 304 wide, where the preview is 0px). `path` is drawn
	// inline under the title instead.
	//
	// Only the entry's own text is searched, which is what the old launcher did
	// with a menu: its haystack was [Text, Subtext, ...Keywords], and no menu in
	// cypher-shell/menus defines a subtext or keywords, so that list is just
	// [Text]. The path is deliberately not searchable, matching the old
	// behaviour (search_name was off by default).
	function menuItems(menuName, withPath) {
		var menus = menuData && menuData.menus ? menuData.menus : null
		if (!menus || !menus[menuName])
			return []

		var menu = menus[menuName]
		var path = withPath && menuName !== "main" ? (menu.pretty || menuName) : ""
		var entries = menu.entries || []
		var out = []
		for (var i = 0; i < entries.length; i++) {
			var e = entries[i]
			out.push({
				text: e.text,
				fields: [e.text],
				// elephant's menucfg.go default.
				minScore: 10,
				subtext: "",
				path: path,
				icon: e.icon || "",
				weight: e.weight || 0,
				kind: "menu",
				action: e.action || ""
			})
		}
		return out
	}

	function providerItems(name, withPath) {
		if (name === "dmenu")
			return items
		if (name.indexOf("menus:") === 0)
			return menuItems(name.slice(6), withPath)
		if (name === "desktopapplications")
			return apps
		if (name === "runner")
			return Providers.runnerItems(runnerList)
		if (name === "symbols")
			return Providers.symbolItems(emojiItems)
		// The grid is the picker's own view, built by rebuildEmoji().
		if (name === "emoji")
			return []
		if (name === "clipboard")
			return Providers.clipboardItems(clipboardHistory)
		if (name === "websearch")
			return Providers.websearchItems(queryText())
		if (name === "providerlist")
			return Providers.providerListItems(menuNames(), menuData.menus)
		if (name === "files" || name === "calc")
			return dynamicItems
		return []
	}

	function buildItems() {
		var names = providerNames()
		// A single provider is being browsed, not searched, so its entries do not
		// need to say which menu they are in.
		var withPath = names.length > 1
		var out = []
		for (var i = 0; i < names.length; i++)
			out = out.concat(providerItems(names[i], withPath))
		return out
	}

	function activeProvider() {
		if (mode !== "")
			return mode
		return Query.resolveQuery(query).provider
	}

	// The text the provider should work on. Prefix triggers only apply to the
	// free-form query: once a mode is fixed (by -m or the provider list) the
	// whole query belongs to that provider. Without this, an absolute path in the
	// files provider would lose its leading "/" to the provider list prefix.
	function queryText() {
		if (mode !== "")
			return query
		return Query.resolveQuery(query).text
	}

	function rebuild() {
		var name = activeProvider()

		if (name === "emoji") {
			rebuildEmoji()
			return
		}

		// files and calc are produced by a process; ask it and show its answer.
		if (name === "files" || name === "calc") {
			dynamicTimer.target = name
			dynamicTimer.restart()
			return
		}

		items = buildItems()
		results = Query.rank(items, queryText())
		selected = results.length > 0 ? 0 : -1
	}

	// ── emoji picker ─────────────────────────────────────────────────────────
	//
	// The grid is not a ranked list: EmojiData decides what is shown (the history
	// first, then the categories, or a flat search) and returns rows for the
	// view. `results` is the same content flattened, because that is what the
	// selection index and the activation path already work on.

	function rebuildEmoji() {
		var built = EmojiData.build(emojiItems, query, emojiGroupIndex, emojiUsage, emojiTone)
		var model = EmojiData.buildRows(built.sections, Metrics.emojiColumns)

		emojiRows = model.rows
		results = flattenSections(built.sections)
		emojiSearching = built.searching
		selected = results.length > 0 ? 0 : -1
	}

	// Tabs in strip order, All first, so movement can walk from one to the next.
	function emojiTabOrder() {
		var order = [-1]
		var groups = emojiData.groups ? emojiData.groups.length : 0
		for (var i = 0; i < groups; i++)
			order.push(i)
		return order
	}

	// Steps to the nearest tab in `direction` that has anything in it, landing on
	// its first emoji going forwards and its last going back. This is what makes
	// the picker read as one continuous scroll rather than a set of islands: down
	// off the end of a category continues into the next one.
	function stepEmojiTab(direction, fromStart) {
		var order = emojiTabOrder()
		var at = order.indexOf(emojiGroupIndex)
		if (at < 0)
			at = 0

		for (var step = 1; step < order.length; step++) {
			var idx = (at + direction * step) % order.length
			if (idx < 0)
				idx += order.length
			setEmojiGroup(order[idx])
			if (results.length > 0) {
				selected = fromStart ? 0 : results.length - 1
				return
			}
		}

		// Every tab is empty, which only happens with no categories at all.
		selected = results.length > 0 ? (fromStart ? results.length - 1 : 0) : -1
	}

	function moveEmoji(delta) {
		if (results.length === 0) {
			// An empty page still has to move somewhere: the history is empty
			// until you have picked something, so the first press should carry
			// you into the categories rather than do nothing.
			stepEmojiTab(delta < 0 ? -1 : 1, delta >= 0)
			return
		}

		// Up and down move by a whole row, so they are recognised by the step
		// being a multiple of the column count: only those cross a tab boundary.
		var vertical = delta % Metrics.emojiColumns === 0
		var next = selected + delta

		if (next >= 0 && next < results.length) {
			selected = next
			return
		}

		if (!vertical) {
			// Left and right stay inside the tab and wrap around it, the way the
			// list wraps.
			selected = next < 0 ? results.length - 1 : 0
			return
		}

		stepEmojiTab(next < 0 ? -1 : 1, next >= 0)
	}

	function flattenSections(sections) {
		var out = []
		for (var i = 0; i < sections.length; i++)
			out = out.concat(sections[i].items)
		return out
	}

	// -1 is the All tab; 0 onwards is a group.
	function setEmojiGroup(index) {
		emojiGroupIndex = index
		rebuildEmoji()
	}

	function tabMoved(delta) {
		var groups = emojiData.groups ? emojiData.groups.length : 0
		var next = emojiGroupIndex + delta
		if (next < -1)
			next = groups - 1
		if (next > groups - 1)
			next = -1
		setEmojiGroup(next)
	}

	// Cycles neutral -> the five tones -> neutral.
	function toneCycled() {
		var count = EmojiData.TONE_MODIFIERS.length
		var next = emojiTone + 1
		setEmojiTone(next >= count ? -1 : next)
	}

	function setEmojiTone(tone) {
		emojiTone = tone
		saveEmojiState()
		rebuildEmoji()
	}

	// Picking copies and pastes, like the list's emoji entries, and counts the
	// pick so the emoji shows up under "Frequently Used".
	function copyEmoji(item) {
		var value = EmojiData.displayChar(item, emojiTone)

		var usage = {}
		for (var key in emojiUsage)
			usage[key] = emojiUsage[key]
		var previous = usage[item.h]
		var count = typeof previous === "number" ? previous : (previous && previous.n ? previous.n : 0)
		// Recency is kept alongside the count so the history can sort a
		// just-picked emoji above one used as often but long ago.
		usage[item.h] = { n: count + 1, t: Date.now() }
		emojiUsage = usage
		saveEmojiState()

		hide()
		Quickshell.execDetached(["bash", "-lc",
			"printf '%s' " + shellQuote(value) + " | wl-copy && clipboard-paste"])
	}

	// ── actions ──────────────────────────────────────────────────────────────

	// The menu TOMLs navigate with `cypher-menu -m X` and close with
	// `cypher-menu --close`, so both are handled in-process: switching mode keeps
	// the launcher open instead of spawning a second one.
	//
	// `walker` is still accepted as the verb, because menu entries that older
	// installs appended to their own keybinds.toml (the PWA and Windows-VM
	// installers write there) spell it that way. New entries are written as
	// `cypher-menu`.
	function navigationTarget(action) {
		var parts = action.split(/\s+/)
		if (parts[0] !== "walker" && parts[0] !== "cypher-menu")
			return null

		var target = { mode: "", theme: "", width: "" }
		for (var i = 1; i < parts.length; i++) {
			var p = parts[i]
			if ((p === "-m" || p === "--provider") && parts[i + 1]) target.mode = parts[++i]
			else if ((p === "-t" || p === "--theme") && parts[i + 1]) target.theme = parts[++i]
			else if ((p === "-w" || p === "--width") && parts[i + 1]) target.width = parts[++i]
			else if (p === "--close" || p === "-q") target.close = true
		}
		return target
	}

	function runAction(action) {
		var a = (action || "").trim()
		if (a === "") {
			hide()
			return
		}

		var target = navigationTarget(a)
		if (target) {
			if (target.close) {
				hide()
				return
			}
			// In-place navigation: same window, new provider.
			mode = target.mode
			if (target.theme !== "") theme = target.theme
			if (target.width !== "") widthArg = target.width
			placeholderArg = ""
			query = ""
			box.clear()
			rebuild()
			return
		}

		hide()
		Quickshell.execDetached(["bash", "-lc", a])
	}

	// Mirror what elephant does with a Terminal=true entry, and strip the
	// field codes that cannot be honoured from here.
	function appCommand(app) {
		var exec = (app.execString || "").replace(/%%/g, "\u0000")
		exec = exec.replace(/%[fFuUdDnNickvm]/g, "").replace(/\u0000/g, "%").trim()
		if (exec === "")
			return ""

		var cmd = exec
		if (app.workingDirectory)
			cmd = "cd '" + String(app.workingDirectory).replace(/'/g, "'\\''") + "' && " + cmd
		if (app.runInTerminal)
			cmd = terminalCmd + " " + cmd
		return cmd
	}

	function activate(index) {
		var item = results[index]
		if (!item)
			return

		if (dmenuMode) {
			finishDmenu(dmenuIndex ? item.srcIndex : item.text)
			return
		}

		if (item.kind === "app") {
			var cmd = appCommand(item.app)
			hide()
			if (cmd !== "")
				Quickshell.execDetached(["bash", "-lc", cmd])
			return
		}

		if (item.kind === "runner") {
			hide()
			Quickshell.execDetached([item.path])
			return
		}

		// The picker's entries carry no `kind`: in that mode every item is an
		// emoji and activation is always a copy.
		if (emojiMode) {
			copyEmoji(item)
			return
		}

		if (item.kind === "symbol" || item.kind === "clipboard") {
			copyAndPaste(item.value, Providers.isFileUriList(item.value))
			return
		}

		// An image is bytes on disk rather than a string, so it is copied by type
		// from the file. It used to stop there, on the reasoning that an image
		// cannot be *typed* into a window -- but the paste is Shift+Insert, not
		// typing, and the target app picks up image/png from it. elephant pastes
		// images the same way as text (its configured command is
		// `wl-copy && clipboard-paste` for every entry), so this does too.
		if (item.kind === "clipboard-image") {
			copyImageAndPaste(item.value, item.mime)
			return
		}

		if (item.kind === "calc") {
			hide()
			Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(item.value) + " | wl-copy"])
			return
		}

		if (item.kind === "websearch") {
			hide()
			Quickshell.execDetached(["xdg-open", item.url])
			return
		}

		if (item.kind === "file") {
			if (item.isDir) {
				query = item.path + "/"
				box.setText(query)
				rebuild()
			} else {
				hide()
				Quickshell.execDetached(["xdg-open", item.path])
			}
			return
		}

		if (item.kind === "provider") {
			mode = item.provider
			query = ""
			box.clear()
			rebuild()
			return
		}

		runAction(item.action)
	}

	function shellQuote(text) {
		return "'" + String(text).replace(/'/g, "'\\''") + "'"
	}

	function stateJson() {
		var sample = []
		for (var i = 0; i < Math.min(3, root.results.length); i++) {
			var row = root.results[i]

			// Picker entries report the glyph as it would be drawn, tone and all,
			// so a tone can be checked without looking at the screen.
			if (root.emojiMode) {
				sample.push(EmojiData.displayChar(row, root.emojiTone) + " " + row.l
					+ " :" + ((row.s && row.s[0]) || "") + ":")
				continue
			}

			var extra = row.path || row.subtext || ""
			sample.push((row.text || "") + (extra ? " | " + extra : ""))
		}
		return JSON.stringify({
			open: root.open,
			mode: root.mode,
			provider: root.activeProvider(),
			set: root.providerNames().join(","),
			query: root.query,
			count: root.results.length,
			selected: root.selected,
			// Picker state, so a test can see the category, tone and grid rows.
			emoji: root.emojiMode,
			group: root.emojiGroupIndex,
			tone: root.emojiTone,
			rows: root.emojiRows.length,
			searching: root.emojiSearching,
			used: Object.keys(root.emojiUsage).length,
			sample: sample
		})
	}

	// What elephant does for clipboard and symbol entries: copy, then let
	// clipboard-paste put it into the focused window -- it waits for the launcher
	// to disappear first, which is why this closes before running it.
	function copyAndPaste(value, uriList) {
		hide()
		var cmd = "printf '%s' " + shellQuote(value) + " | wl-copy && clipboard-paste"
		if (uriList)
			cmd += " -t text/uri-list"
		Quickshell.execDetached(["bash", "-lc", cmd])
	}

	// The image half of the same thing: the file is the payload instead of a
	// string, and the type comes from the history entry (which took it from the
	// clipboard's own type list), so the pasted bytes are what was copied rather
	// than whatever wl-copy would infer.
	function copyImageAndPaste(file, mime) {
		hide()
		Quickshell.execDetached(["bash", "-lc",
			"wl-copy -t " + shellQuote(mime) + " < " + shellQuote(file) + " && clipboard-paste"])
	}

	function move(delta) {
		if (emojiMode) {
			moveEmoji(delta)
			return
		}

		if (results.length === 0) {
			selected = -1
			return
		}
		// selection_wrap = true
		var next = selected + delta
		if (next < 0)
			next = results.length - 1
		if (next >= results.length)
			next = 0
		selected = next
	}

	// Home and End are absolute, not relative moves. They used to be sent as
	// +/-results.length through move(), which is off by one wrap in both
	// directions: Home landed on the last item and End on the first.
	function jump(toEnd) {
		if (results.length === 0) {
			selected = -1
			return
		}
		selected = toEnd ? results.length - 1 : 0
	}

	// ── open / close ─────────────────────────────────────────────────────────

	function show() {
		open = true
		box.clear()
		rebuild()
		box.focusInput()
	}

	function hide() {
		open = false
		box.clear()
		dynamicItems = []
		dmenuMode = false
		dmenuFifo = ""
		query = ""
		mode = ""
		placeholderArg = ""
		items = []
		results = []
		selected = -1
		emojiRows = []
		emojiGroupIndex = -1
	}

	function applyOptions(raw) {
		var opts = {}
		try {
			opts = JSON.parse(raw || "{}")
		} catch (e) {
			console.warn("launcher: bad options: " + e)
		}

		mode = opts.mode || ""
		theme = opts.theme || "default"
		widthArg = opts.width || ""
		placeholderArg = opts.placeholder || ""
		showSearch = !truthy(opts.nosearch)
		showHints = !truthy(opts.nohints)
		query = ""
		box.clear()
	}

	// cypher-menu builds the options with printf, so these arrive as the numbers
	// 0 and 1 rather than booleans -- comparing against `true` alone silently
	// ignored -n and -N.
	function truthy(value) {
		return value === true || value === 1 || value === "1" || value === "true"
	}

	// ── dmenu ────────────────────────────────────────────────────────────────

	function startDmenu(payload, fifo, index, password, placeholder) {
		dmenuMode = true
		dmenuFifo = fifo
		dmenuIndex = index === "1"
		mode = ""
		theme = "default"
		widthArg = ""
		showHints = true
		placeholderArg = placeholder || "  Selection..."
		query = ""
		box.clear()

		var lines = String(payload).replace(/\n$/, "").split("\n")
		var out = []
		for (var i = 0; i < lines.length; i++) {
			out.push({
				text: lines[i],
				subtext: "",
				keywords: "",
				icon: "",
				weight: 0,
				kind: "dmenu",
				srcIndex: i
			})
		}
		items = out
		results = Query.rank(items, "")
		selected = results.length > 0 ? 0 : -1
		open = true
	}

	// Writes the pick to the caller's FIFO. A cancel writes an empty line so the
	// waiting reader returns immediately instead of sitting out its timeout.
	Process {
		id: fifoWriter

		property string value
		property string fifo

		command: ["bash", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "fifo-writer", value, fifo]
	}

	function finishDmenu(value) {
		var fifo = dmenuFifo
		hide()
		if (fifo === "")
			return
		fifoWriter.value = value === undefined || value === null ? "" : String(value)
		fifoWriter.fifo = fifo
		fifoWriter.running = true
	}

	// ── IPC ──────────────────────────────────────────────────────────────────

	IpcHandler {
		target: "launcher"

		function open(opts: string): string {
			root.applyOptions(opts)
			root.show()
			return "ok"
		}

		function close(): string {
			root.hide()
			return "ok"
		}

		// A bare `cypher-menu` toggles: SUPER opens the main menu, and pressing it
		// again closes whatever is showing. The options are applied either way so
		// the next open is correctly configured.
		function toggle(opts: string): string {
			var wasOpen = root.open
			root.applyOptions(opts)
			if (wasOpen) {
				root.hide()
				return "closed"
			}
			root.show()
			return "opened"
		}

		function reload(): string {
			menuFile.reload()
			providersGen.running = true
			clipboardFile.reload()
			root.refreshApps()
			return "ok"
		}

		// Read-only introspection, used to check the launcher from a script or a
		// test rather than by looking at the screen.
		function state(): string {
			return root.stateJson()
		}

		// Types into the launcher without a keyboard. Synthetic input cannot drive
		// it (wtype's virtual keyboard reports a broken keymap to Hyprland, so
		// every key resolves to Escape), and the picker's search, tabs and tones
		// need to be checkable, so the query is settable over IPC.
		function filter(text: string): string {
			root.query = text
			box.setText(text)
			root.rebuild()
			return root.stateJson()
		}

		// Switches the picker's category and tone, which the grid's tabs and
		// swatches do with a click.
		function picker(group: string, tone: string): string {
			if (group !== "")
				root.setEmojiGroup(parseInt(group, 10))
			if (tone !== "")
				root.setEmojiTone(parseInt(tone, 10))
			return root.stateJson()
		}

		// Activates a result by index, the way enter or a click does. Same reason
		// as filter(): there is no synthetic keyboard on this session.
		function pick(index: string): string {
			root.activate(parseInt(index, 10))
			return "ok"
		}

		// Moves the selection, as the arrow keys do. Same reason again.
		function move(delta: string): string {
			root.move(parseInt(delta, 10))
			return root.stateJson()
		}

		function jump(to_end: string): string {
			root.jump(root.truthy(to_end))
			return root.stateJson()
		}

		function dmenu(payload: string, fifo: string, index: string, password: string, placeholder: string): string {
			root.startDmenu(payload, fifo, index, password, placeholder)
			return "ok"
		}
	}

	// ── the window ───────────────────────────────────────────────────────────

	screen: {
		var monitors = Hyprland.monitors.values
		for (var i = 0; i < monitors.length; i++) {
			var m = monitors[i]
			if (m.lastIpcObject && m.lastIpcObject.focused) {
				for (var j = 0; j < Quickshell.screens.length; j++)
					if (Quickshell.screens[j].name === m.name)
						return Quickshell.screens[j]
			}
		}
		return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
	}

	visible: open
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "quickshell:launcher"
	// Only take the keyboard while the launcher is up; a stale exclusive surface
	// would swallow every keystroke on the session.
	WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore

	anchors {
		top: true
		bottom: true
		left: true
		right: true
	}

	// Clicking outside the box dismisses, like walker.
	MouseArea {
		anchors.fill: parent
		onClicked: root.hide()
	}

	Box {
		id: box

		anchors.centerIn: parent
		visible: root.open

		palette: root.palette
		theme: root.theme
		placeholder: Query.placeholderFor(root.mode, root.placeholderArg)
		showSearch: root.showSearch
		showHints: root.showHints
		results: root.results
		selected: root.selected
		requestedWidth: Metrics.boxWidthFor(root.widthArg)

		// Picker state. The hovered cell stays inside the box: it is presentation
		// only and never touches the selection.
		emojiMode: root.emojiMode
		emojiRows: root.emojiRows
		emojiGroups: root.emojiData.groups ? root.emojiData.groups : []
		emojiTone: root.emojiTone
		emojiGroupIndex: root.emojiGroupIndex
		emojiSearching: root.emojiSearching

		onActivated: function(index) { root.activate(index) }
		onMoved: function(delta) { root.move(delta) }
		onJumped: function(toEnd) { root.jump(toEnd) }
		onDismissed: root.hide()
		onTabMoved: function(delta) { root.tabMoved(delta) }
		onToneCycled: root.toneCycled()
		onToneSelected: function(tone) { root.setEmojiTone(tone) }
		onEmojiTabRequested: function(index) { root.setEmojiGroup(index) }

		// Typing filters. The query lives on the window so the provider set can
		// react to a prefix like "=" or ":".
		onQueryEdited: function(text) {
			root.query = text
			root.rebuild()
		}
	}
}
