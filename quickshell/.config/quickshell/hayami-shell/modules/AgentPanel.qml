pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme.js" as Theme

// The agent module's popout: what the agent is doing, and what it is spending.
//
// The module itself has room for a glyph and nothing else, so the panel is where
// the reading lives -- which agent, which project, how long it has been up, and
// the Freebucks it is drawing on. It shows what the module already read (see
// AgentIndicator) rather than probing again, so the icon and the card cannot
// disagree.
//
// When more than one session is live, the card shows a row for each of them and
// a reading for the one under the mark: "which agent" is a question a
// single-model card cannot answer.
//
// Shaped like the VPN panel, and a layer surface for the same reason (see
// VpnPanel and CalendarPanel): a surface the compositor places has no parent for
// a grab to get refused on, its size is its content's, and it holds the keyboard
// while it is up.
Item {
	id: root

	// ── handed down by the agent module ──────────────────────────────────────

	property var pal: null
	property string edge: "top"
	property var screenModel: null
	// The module's own corner inside the bar's surface, and how much of the bar
	// it takes up there, so the panel centres on the module.
	property point anchor: Qt.point(0, 0)
	property size anchorSize: Qt.size(0, 0)

	property bool live: false

	// Which agent this reading is about, as its own window title spells it:
	// "Freebuff" today, whatever you launch sessions with tomorrow. Handed down
	// by the module rather than decided here, so the card and the bar cannot
	// disagree about what they are looking at.
	property string provider: ""

	// Every live session, in the order the script read them -- most urgent
	// first. What the card shows is the one under the mark; the rest are the
	// rows waiting for it.
	property var sessions: []
	property bool loggedIn: false
	property int balance: 0
	property int dailyLimit: 0
	property int dailySpent: 0
	property int dailyRemaining: 0
	property string dailyResetAt: ""
	property int wallet: 0
	property string tier: ""
	property int streak: 0
	property string note: ""

	// Whether the card is up. It is *bound* by the module to the shell's shared
	// flag (BarState.agentPanel, narrowed to this monitor's bar), not toggled
	// here: SUPER+A and a click on the module are two ways into one setting, so
	// neither can close a card the other opened.
	property bool open: false

	// Escape and a click off the card. The panel does not write the shared flag
	// itself -- the module owns the road back to BarState.
	signal dismissed()

	// Starting a session, asked for rather than done. The panel draws and emits;
	// the module is what reaches the rest of the system -- the same division that
	// keeps this card from writing the shared panel flag itself.
	signal launchRequested()

	// ── which of them ────────────────────────────────────────────────────────
	//
	// Several agents can be live at once, so the card shows one reading and a row
	// per session: this is the index of the row under the mark. It stays here and
	// not in the bar state because it means nothing outside the card -- the flag
	// that says whether the card is up is the only thing the keybind and the
	// module's own click have to agree on.
	property int selected: 0

	readonly property int count: sessions.length

	readonly property var current: selected >= 0 && selected < count
		? sessions[selected] : null

	// A session can end while the card is up, and the list is re-read every five
	// seconds: the mark follows the list rather than pointing past its end.
	onSessionsChanged: if (selected > count - 1)
		selected = Math.max(0, count - 1)

	function moveSelection(delta) {
		if (count === 0)
			return
		selected = Math.max(0, Math.min(count - 1, selected + delta))
	}

	// ── the palette ──────────────────────────────────────────────────────────

	readonly property bool vertical: Theme.isVertical(edge)
	readonly property color foreground: pal ? pal.foreground : "#c5c4c4"
	readonly property color background: pal ? pal.background : "#171513"
	// The accent every list in this shell marks focus with.
	readonly property color accent: pal && pal.colors && pal.colors.length > 3
		? pal.colors[3] : (pal && pal.accent ? pal.accent : "#CEA56A")
	// A row's badge, in the same three colours the bar's own badge uses and for the
	// same reasons: the dot on the glyph and the dot on a row are one signal in
	// two places, so they take their colour from one function rather than each
	// carrying a copy of the rule.
	//
	// The fallbacks are BarPalette.qml's own values, repeated exactly. They were
	// drifting -- the working one here was a different green from the palette's,
	// so a card opened before the palette loaded would have shown a badge the
	// bar had never drawn. Same string in both places, on purpose.
	readonly property color waitingColor: pal && pal.waiting ? pal.waiting : "#e06c9f"
	readonly property color finishedColor: pal && pal.finished ? pal.finished : "#e5c07b"
	readonly property color workingColor: pal && pal.working ? pal.working : "#88b667"
	readonly property color idleColor: pal && pal.idle ? pal.idle : "#7a7a7a"

	function statusColor(status) {
		if (status === "waiting")
			return waitingColor
		if (status === "finished")
			return finishedColor
		if (status === "idle")
			return idleColor
		return workingColor
	}

	// Whether a row's state earns a dot at all. Every state does, including
	// idle: the bar's badge withholds one from idle because a badge claims
	// something needs you, but a row in a list is not claiming that. A session
	// with no dot read as a gap in the list rather than as a state, and the
	// list is exactly where you go to find out what every session is doing.
	// Only a status the script did not supply at all goes undotted.
	function hasDot(status) {
		return status !== undefined && status !== ""
	}

	// The same states in words. A colour is a glance and not a reading, and this is
	// the one place on the card that can afford to spell it out.
	//
	// `waiting` is spelled "needs input" rather than "waiting" because that is what
	// it is asking: nothing is happening until you answer, and a row that says
	// only "waiting" could be read as waiting *with* you. `idle` is spelled with
	// the same word the script uses, so the reading here and the state in
	// agent-status.sh cannot drift apart -- it was "at the prompt" for a while,
	// which described the cause rather than the state.
	function statusWord(status) {
		if (status === "waiting")
			return "needs input"
		if (status === "finished")
			return "finished"
		if (status === "working")
			return "working"
		if (status === "idle")
			return "idle"
		return ""
	}

	readonly property string fontFamily: Theme.fontFamily

	// Dimmed text as a mix towards the panel's own background rather than
	// Qt.darker(), which only dims a light-on-dark theme -- the VPN panel and the
	// calendar both carry their own copy of this for the same reason.
	function shade(color, mix) {
		var b = root.background
		return Qt.rgba(color.r + (b.r - color.r) * mix,
			color.g + (b.g - color.g) * mix,
			color.b + (b.b - color.b) * mix, 1)
	}

	readonly property color dimText: shade(foreground, 0.35)
	readonly property color dimmerText: shade(foreground, 0.6)

	// ── the reading ──────────────────────────────────────────────────────────

	// "2h 34m": the two units that matter at a glance, and no more -- a session
	// age is read to know roughly how long something has been running.
	function fmtAge(s) {
		if (!s || s <= 0)
			return "-"
		var d = Math.floor(s / 86400)
		var h = Math.floor((s % 86400) / 3600)
		var m = Math.floor((s % 3600) / 60)
		if (d > 0)
			return d + "d " + h + "h"
		if (h > 0)
			return h + "h " + m + "m"
		if (m > 0)
			return m + "m"
		return s + "s"
	}

	// When the daily allowance comes back, as a countdown rather than a clock
	// time: the reset is announced in UTC by the API's own timezone, and a
	// wall-clock time would be a second thing to get wrong.
	function resetIn(iso) {
		if (!iso)
			return ""
		var t = Date.parse(iso)
		if (isNaN(t))
			return ""
		var diff = Math.floor((t - Date.now()) / 1000)
		if (diff <= 0)
			return "now"
		return "in " + fmtAge(diff)
	}

	// The heading says what this card is *about*, not what one session is doing:
	// "Agents", always, whatever is up. A heading that changed with the state
	// made the card a different card each time you opened it, and it had no room
	// left for a count once it was naming a model -- which the list still does,
	// one per row, where two sessions are told apart.
	readonly property string heading: "Agents"

	// Who you are looking at. Split out from the state beside it rather than
	// concatenated into one string, because the two are not the same kind of
	// thing: this is the name of the thing, and it is set in bold, while the
	// state changes under you and is not. One Text with the name typed into it
	// would have to be bold all the way through, or regular all the way through.
	//
	// The fallback is for the first frame after the panel opens and before the
	// module's first reading lands, which is the only time provider is empty.
	readonly property string providerName: provider !== "" ? provider : "Agent"

	readonly property bool hasUsage: loggedIn && dailyLimit > 0
	// What the meter under "Today" shows: how much of the day's allowance is
	// still there. Full is all of it, and it drains as you spend.
	//
	// The bar and the number above it are the same quantity in the same
	// direction, on purpose. They were once "remaining" on the bar and
	// "remaining" in the text, then briefly "spent" on the bar and "remaining"
	// in the text -- which put "100 / 100" next to an empty bar, and a bar that
	// disagrees with the number beside it is worse than either choice on its
	// own. If this is ever changed, change the text at the same time.
	//
	// Available rather than spent, because that is the half you can act on: the
	// card is opened to find out what there is left to spend today, and showing
	// the remainder makes the reader do the subtraction themselves.
	readonly property real dailyAvailableFraction: dailyLimit > 0
		? Math.max(0, Math.min(1, dailyRemaining / dailyLimit)) : 0

	// The selected session's own numbers, priced off its own model: two agents on
	// different models cost different rates, which is why the rate is read per
	// session and not once for the card. The directory is not repeated here -- it
	// is the row above it, under the mark.
	readonly property var rows: {
		if (!current)
			return []
		var out = []
		// First, because it is the answer to "why am I looking at this" and
		// everything under it is detail. Carries its own colour so the row says
		// the same thing twice over.
		var word = statusWord(current.status)
		if (word !== "")
			out.push({ label: "Status", value: word, color: statusColor(current.status) })
		if (current.price > 0) {
			var rate = current.price + " FB/hr"
			if (current.offPeak)
				rate += "  ·  off-peak"
			out.push({ label: "Rate", value: rate })
		}
		if (current.since > 0)
			out.push({ label: "Running", value: fmtAge(current.since) })
		return out
	}

	readonly property var walletRows: {
		var out = []
		out.push({ label: "Wallet", value: wallet + " FB" })
		out.push({ label: "Total", value: balance + " FB" })
		if (streak > 0)
			out.push({ label: "Streak", value: streak + " days" })
		var reset = resetIn(dailyResetAt)
		if (reset !== "")
			out.push({ label: "Resets", value: reset })
		return out
	}

	// ── where the panel goes ─────────────────────────────────────────────────
	//
	// The VPN panel's arithmetic, because a flyout off the bar is the same
	// problem: just past the bar on the axis the bar's thickness occupies, and
	// centred on the module that opened it along the axis the bar runs -- clamped
	// so the whole card stays on screen.

	readonly property real pastBar: Theme.marginTop + Theme.thicknessFor(edge)
		+ Theme.agentPanelBarGap
	readonly property real screenW: screenModel ? screenModel.width : 0
	readonly property real screenH: screenModel ? screenModel.height : 0

	readonly property real barOriginX: edge === "right"
		? screenW - Theme.thicknessFor(edge) - Theme.marginTop
		: (edge === "left" ? Theme.marginTop : Theme.marginSide)
	readonly property real barOriginY: edge === "bottom"
		? screenH - Theme.thicknessFor(edge) - Theme.marginTop
		: (edge === "top" ? Theme.marginTop : Theme.marginSide)

	readonly property real followX: Math.max(Theme.marginSide,
		Math.min(barOriginX + anchor.x + anchorSize.width / 2 - cardW / 2,
			screenW - cardW - Theme.marginSide))
	readonly property real followY: Math.max(Theme.marginSide,
		Math.min(barOriginY + anchor.y + anchorSize.height / 2 - cardH / 2,
			screenH - cardH - Theme.marginSide))

	// Read once, as the panel opens, and kept while it is up -- the same call the
	// calendar and the VPN panel make: the module drifts for reasons that have
	// nothing to do with this panel, and a card that jumped for those would be
	// the worse trade.
	property real panelX: 0
	property real panelY: 0

	function takePlace() {
		panelX = followX
		panelY = followY
	}

	readonly property real cardW: Theme.agentPanelWidth
	readonly property real cardH: column.implicitHeight
		+ (Theme.agentPanelPad + Theme.agentPanelBorderWidth) * 2
	readonly property real cardX: vertical
		? (edge === "left" ? pastBar : screenW - pastBar - cardW)
		: panelX
	readonly property real cardY: vertical
		? panelY
		: (edge === "top" ? pastBar : screenH - pastBar - cardH)

	onOpenChanged: {
		if (!open)
			return
		// The mark starts on the first session every time the card comes up,
		// rather than on whatever was selected the last time it was open.
		selected = 0
		takePlace()
		keys.forceActiveFocus()
	}

	// ── the keyboard ─────────────────────────────────────────────────────────
	//
	// What each key means while the panel is up: hjkl and the arrows walk the
	// list of sessions, and space or enter goes to the window of the one under
	// the mark -- the pair VpnPanel binds, for the same reason (its one row is
	// what this card keeps a list of).
	//
	// The handler that feeds these keys is declared inside the panel window
	// below, not here: a key handler only ever sees the keys of the window it is
	// declared in, and this object is declared in the bar's window, which holds
	// no keyboard at all.

	QtObject {
		id: keymap

		function handleKey(event) {
			switch (event.key) {
			case Qt.Key_Left:
			case Qt.Key_H:
			case Qt.Key_Up:
			case Qt.Key_K:
				root.moveSelection(-1)
				event.accepted = true
				break
			case Qt.Key_Right:
			case Qt.Key_L:
			case Qt.Key_Down:
			case Qt.Key_J:
				root.moveSelection(1)
				event.accepted = true
				break
			case Qt.Key_Space:
			case Qt.Key_Return:
			case Qt.Key_Enter:
				root.focusSession(root.selected)
				event.accepted = true
				break
			}
		}
	}

	// Go to a session's terminal. The address came from the reading in
	// agent-status.sh, which walks the process chain to find the window the CLI is
	// running in -- the panel only has to hand it to the compositor, which takes
	// the focus there, workspace and all.
	//
	// A session with no window is left alone rather than dismissed: its row is
	// still worth reading, and the next one is a keypress away.
	function focusSession(index) {
		// Idle: there is nothing to go to, and the one thing to do here is start
		// something. The row below says so and does exactly this, so the key and
		// the click are the same action rather than two that resemble each other.
		if (!live) {
			launchRequested()
			return
		}
		if (count === 0)
			return
		selected = Math.max(0, Math.min(count - 1, index))
		if (!current || !current.address)
			return
		going.address = current.address
		// The card is closed *before* the focus is asked for, and not after.
		//
		// While this card is up it holds the keyboard exclusively, which is
		// deliberate -- it was opened to be read. But that is exactly what stops
		// a window focus from landing: with a layer surface owning the keyboard
		// the compositor will not move the focused window at all. Measured, not
		// guessed: the same `hl.dsp.focus` moves focus with the card closed and
		// does not move it with the card open, and `focus = true` does not get
		// past it either.
		//
		// The symptom was a focus that looked half-done -- `focuswindow` still
		// warps the cursor to the right window, so the mouse arrived and the
		// keyboard did not. On this machine that is doubly true, because
		// `follow_mouse = 2` detaches the cursor from focus anyway, so the warp
		// never carried focus with it to begin with.
		//
		// So the card closes on the way out after all, which is what the note
		// below used to argue against: it worried that a card vanishing before
		// the focus landed would make the keypress look like it did nothing. A
		// card that closes *and* leaves the focus where it was is the thing that
		// looks like nothing, and that was the bug. The dispatch waits a beat
		// (handOverDelay) for the surface to actually go, since the close and
		// the dispatch are two separate clients of the compositor and nothing
		// orders them.
		dismissed()
		handOverDelay.restart()
	}

	// The card is already closed by the time this runs -- focusSession closes it
	// before asking for the focus, because an open card cannot be focused past.
	//
	// Through `hyprctl eval`, not `hyprctl dispatch`: this Hyprland reads the
	// dispatch argument as Lua, so the older `dispatch focuswindow address:...`
	// string is a syntax error rather than a focus. `hl.dsp.focus` is the
	// dispatcher that takes a window, and `address:` is the selector it wants --
	// the same call hypr-firefox-pwa makes for its popups.
	Process {
		id: going

		property string address: ""

		command: ["hyprctl", "eval",
			"hl.dispatch(hl.dsp.focus({ window = 'address:" + address + "' }))"]

		onExited: address = ""
	}

	// How long after the card closes the focus is asked for. It only has to cover
	// the compositor taking the surface down, which is a frame or two; the rest
	// is margin, and it is not felt -- the card is already gone by the time this
	// starts. It exists because the close and the dispatch are two separate
	// clients of the compositor and nothing orders them, so the focus would
	// otherwise race the card's own unmap and lose.
	Timer {
		id: handOverDelay

		interval: 250
		onTriggered: going.running = true
	}

	// ── the panel ────────────────────────────────────────────────────────────

	PanelWindow {
		id: panel

		screen: root.screenModel
		visible: root.open

		// Full screen, with the card drawn inside it at cardX/cardY -- the shape
		// every popout off the bar uses, and for the same reason: a surface
		// bigger than what it draws lets a click *off* the card put the panel
		// away, with no focus event to interpret.
		anchors.top: true
		anchors.bottom: true
		anchors.left: true
		anchors.right: true

		exclusiveZone: 0
		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Top
		WlrLayershell.namespace: "quickshell:agent"
		// Exclusive while it is up: the panel was opened to be read, so the keys
		// belong to it until escape or a click off the card takes them back.
		// This is also why a row has to close the card before asking for a
		// window focus -- see focusSession.
		WlrLayershell.keyboardFocus: root.open
			? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		// Declared before the box so it stays below it, which is what keeps the
		// card itself clickable.
		MouseArea {
			anchors.fill: parent
			onClicked: root.dismissed()
		}

		FocusScope {
			id: keys

			anchors.fill: parent
			// The same keys the card keeps while it is up.
			focus: root.open

			Keys.onEscapePressed: root.dismissed()
			Keys.onPressed: (event) => keymap.handleKey(event)
		}

		// The box, drawn the way the bar, the tooltips and the calendar draw
		// theirs: a rounded rect in the border colour with the background inset
		// inside it, because Qt centres a border pen on the item's outline and
		// clips the outer half.
		Rectangle {
			x: root.cardX
			y: root.cardY
			width: root.cardW
			height: root.cardH
			color: Theme.borderColor
			radius: Theme.agentPanelRadius

			Rectangle {
				anchors.fill: parent
				anchors.margins: Theme.agentPanelBorderWidth
				color: root.background
				radius: Math.max(Theme.agentPanelRadius - Theme.agentPanelBorderWidth, 0)
			}

			Column {
				id: column

				x: Theme.agentPanelBorderWidth + Theme.agentPanelPad
				y: Theme.agentPanelBorderWidth + Theme.agentPanelPad
				width: root.cardW - (Theme.agentPanelBorderWidth + Theme.agentPanelPad) * 2
				spacing: Theme.agentPanelGap

				// ── the heading ──────────────────────────────────────────────
				//
				// Set as the calendar sets its date: the same size, in bold, in
				// the plain foreground. Two popouts off the same bar that name
				// themselves at two different weights read as two different
				// kinds of card, and this one has no more to say than the
				// calendar's hero line does.
				//
				// No dot beside it. It was saying live or idle, and the
				// subheading now says that in words -- which is the half of the
				// card that changes, so a second signal for it in the title
				// slot was saying the same thing twice, in a corner no eye goes
				// to first.
				//
				// Centred on the card, as the calendar centres its date: the
				// heading is the one line that belongs to the whole card rather
				// than to a column of readings, so it is the one line that
				// should not hang off the left edge with them. The rows below
				// stay left-aligned, because they are the ones being scanned.
				//
				// A direct child of the card's column, not wrapped in one of its
				// own: the rule below belongs between this and the subheading, so
				// a wrapper grouping the two of them would have to be broken
				// open to put it there.
				Text {
					id: headingText

					anchors.horizontalCenter: parent.horizontalCenter
					text: root.heading
					color: root.foreground
					font.family: root.fontFamily
					font.pixelSize: Theme.agentPanelNameSize
					font.bold: true
				}

				// ── the rule under the heading ─────────────────────────────────
				//
				// Above the provider, not below it. Everything under this line
				// is a reading -- who is running, what it is costing, what is
				// left of today -- and everything above it is the name of the
				// card. Putting the rule under the subheading instead left the
				// provider and the state stranded above the line, looking like
				// part of the title when it is a reading like any other.
				//
				// The air above and below it is the column's own spacing, so it
				// sits the same distance from the heading in this card as the
				// calendar's does in its own.
				Rectangle {
					width: parent.width
					height: Theme.panelDividerWidth
					color: root.shade(root.foreground, Theme.panelDividerMix)
				}

				// The provider, alone, while there is only one. What it is *doing*
				// is not said here: the dot on the bar's glyph, and the
				// coloured dot on each row below, already carry that, and
				// the selected session spells its own state out in the
				// readings. The card names itself "Agents" above this, so
				// this line is only ever the product.
				Text {
					width: parent.width
					text: root.providerName
					color: root.dimText
					font.family: root.fontFamily
					font.pixelSize: Theme.agentPanelProviderSize
					font.bold: true
					elide: Text.ElideRight
				}

				// ── the session list ─────────────────────────────────────────
				//
				// One row per live session: several agents can be running in
				// different directories, and the card can only show one reading at a
				// time, so the list is what says which. The row under the mark is the
				// selected one -- hjkl or the arrows move it, space or enter goes to
				// its window -- and the mark is the accent bar every list in the
				// shell uses for its focused row.
				Column {
					width: parent.width
					spacing: 0
					visible: root.count > 0

					Repeater {
						model: root.sessions

						delegate: Item {
							id: sessionRow

							required property var modelData
							required property int index

							readonly property bool marked: root.selected === index

							width: column.width
							height: Theme.agentPanelRowHeight

							Rectangle {
								anchors.left: parent.left
								anchors.verticalCenter: parent.verticalCenter
								width: Theme.agentPanelMarkWidth
								height: Theme.agentPanelMarkHeight
								color: root.accent
								// The keyboard's row and the
								// pointer's own get the same cue,
								// so hovering shows what a click
								// would go to.
								visible: sessionRow.marked || sessionMouse.containsMouse
							}

							Text {
								anchors.left: parent.left
								anchors.leftMargin: Theme.agentPanelMarkWidth + 8
								anchors.right: sessionModel.left
								anchors.rightMargin: 8
								anchors.verticalCenter: parent.verticalCenter
								text: sessionRow.modelData.project !== ""
									? sessionRow.modelData.project : "no directory"
								color: (sessionRow.marked || sessionMouse.containsMouse)
									? root.accent : root.foreground
								font.family: root.fontFamily
								font.pixelSize: Theme.agentPanelStatusSize
								elide: Text.ElideMiddle
							}

						// The status badge: the same dot the bar puts on its
						// glyph, in the same three colours, for the same reason
						// -- one signal in two places. It goes at the row's far
						// right, down the same edge as every other row's, so the
						// badges line up into a column rather than trailing
						// their own text.
						//							// Every live row wears one, idle included, in its own colour:
							// gray for idle, which is the point of it. The dot is the
							// row's whole state report at a glance, and "at the prompt"
							// has to be as visible as "needs input" -- it is the same
							// list, read the same way.
						Rectangle {
							id: waitingDot

							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							width: Theme.agentPanelDotSize
							height: Theme.agentPanelDotSize
							radius: width / 2
							color: root.statusColor(sessionRow.modelData.status)
							visible: root.hasDot(sessionRow.modelData.status)
						}

							Text {
								id: sessionModel

								anchors.right: parent.right
								// The badge's space is kept whether the badge is there
								// or not, so that a turn ending moves a dot into a row
								// rather than sliding the row's text sideways.
								anchors.rightMargin: Theme.agentPanelDotSize
									+ Theme.agentPanelBadgeGap
								anchors.verticalCenter: parent.verticalCenter
								// Capped, so that a long
								// model name cannot push the
								// directory out of its own row:
								// the directory is what tells
								// the sessions apart.
								width: Math.min(implicitWidth, parent.width * 0.45)
								text: sessionRow.modelData.modelShort
								color: root.dimmerText
								font.family: root.fontFamily
								font.pixelSize: Theme.agentPanelLabelSize
								horizontalAlignment: Text.AlignRight
								elide: Text.ElideRight
							}

							MouseArea {
								id: sessionMouse

								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.focusSession(sessionRow.index)
							}
						}
					}
				}

				// ── starting one ────────────────────────────────────────────
				//
				// Only while idle, and in the slot the session list would occupy:
				// an idle card is opened *because* there is nothing to read, and a
				// card that says only "idle" makes the reader reach for a key they
				// may not know is bound. This is the same action the key does, one
				// click away -- and it carries its own key on the right, so the
				// binding is discoverable from the card rather than from BINDS.md.
				Item {
					id: launchRow

					width: column.width
					height: Theme.agentPanelRowHeight
					visible: !root.live

					Rectangle {
						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: Theme.agentPanelMarkWidth
						height: Theme.agentPanelMarkHeight
						color: root.accent
						// The same mark a session row carries when it is under
						// it, on the same terms: hovering shows what a click
						// would go to.
						visible: launchMouse.containsMouse
					}

					Text {
						anchors.left: parent.left
						anchors.leftMargin: Theme.agentPanelMarkWidth + 8
						anchors.verticalCenter: parent.verticalCenter
						text: "New session"
						color: launchMouse.containsMouse ? root.accent : root.foreground
						font.family: root.fontFamily
						font.pixelSize: Theme.agentPanelStatusSize
					}

					Text {
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						// Spelled the way menus/keybinds.toml spells a chord.
						text: "SUPER + SHIFT + A"
						color: root.dimmerText
						font.family: root.fontFamily
						font.pixelSize: Theme.agentPanelLabelSize
					}

					MouseArea {
						id: launchMouse

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.launchRequested()
					}
				}

				// What the session under the mark is up to, and what it costs at
				// its own model's rate: the list above says which agent, this says
				// what that one is doing.
				Column {
					width: parent.width
					spacing: 0
					visible: root.rows.length > 0

					Repeater {
						model: root.rows

						delegate: Item {
							required property var modelData

							width: column.width
							height: Theme.agentPanelRowHeight

							Text {
								anchors.left: parent.left
								anchors.verticalCenter: parent.verticalCenter
								text: parent.modelData.label
								color: root.dimmerText
								font.family: root.fontFamily
								font.pixelSize: Theme.agentPanelLabelSize
							}

						Text {
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							anchors.left: parent.left
							anchors.leftMargin: 88
							text: parent.modelData.value
							color: parent.modelData.color
								? parent.modelData.color : root.foreground
							font.family: root.fontFamily
							font.pixelSize: Theme.agentPanelStatusSize
							horizontalAlignment: Text.AlignRight
							elide: Text.ElideMiddle
						}
						}
					}
				}

				// ── what it is spending ──────────────────────────────────────
				//
				// Only while there is a wallet to show. A logged-out shell gets
				// the note at the bottom instead of a row of zeroes, which would
				// read as an empty account rather than an absent one.
				Column {
					width: parent.width
					spacing: 0
					visible: root.hasUsage

					Item {
						width: parent.width
						height: dailyText.implicitHeight

						Text {
							id: dailyText

							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter
							text: "Today"
							color: root.dimmerText
							font.family: root.fontFamily
							font.pixelSize: Theme.agentPanelLabelSize
						}

						Text {
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							text: root.dailyRemaining + " / " + root.dailyLimit + " FB"
							color: root.foreground
							font.family: root.fontFamily
							font.pixelSize: Theme.agentPanelStatusSize
						}
					}

					// The meter: what is left of the day's allowance, draining as
					// you spend. The fill is the accent, so it reads as the
					// same quantity the bar's own meter would, and it agrees
					// with the number above it at every value.
					Item {
						width: parent.width
						height: Theme.agentPanelMeterHeight + 8

						Rectangle {
							id: meterTrack

							anchors.left: parent.left
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							height: Theme.agentPanelMeterHeight
							radius: Theme.agentPanelMeterRadius
							color: root.dimmerText
							opacity: 0.35
						}

						Rectangle {
							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter
							width: Math.max(0, meterTrack.width * root.dailyAvailableFraction)
							height: Theme.agentPanelMeterHeight
							radius: Theme.agentPanelMeterRadius
							color: root.accent
						}
					}

					Repeater {
						model: root.walletRows

						delegate: Item {
							required property var modelData

							width: column.width
							height: Theme.agentPanelRowHeight

							Text {
								anchors.left: parent.left
								anchors.verticalCenter: parent.verticalCenter
								text: parent.modelData.label
								color: root.dimmerText
								font.family: root.fontFamily
								font.pixelSize: Theme.agentPanelLabelSize
							}

							Text {
								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								text: parent.modelData.value
								color: root.foreground
								font.family: root.fontFamily
								font.pixelSize: Theme.agentPanelStatusSize
							}
						}
					}
				}

				// ── when there is nothing to show ────────────────────────────
				Text {
					width: parent.width
					visible: root.note !== ""
					text: root.note
					color: root.dimmerText
					font.family: root.fontFamily
					font.pixelSize: Theme.agentPanelLabelSize
					wrapMode: Text.WordWrap
				}

				// What the list does with the keyboard, said once at the foot of
				// the card. Only the keys that currently do something appear:
				// a footer listing a key that has one row to move through is
				// telling the reader about a control that is not there.
				Text {
					width: parent.width
					visible: root.count > 1
					text: "j / k to switch  ·  space to focus"
					color: root.dimmerText
					font.family: root.fontFamily
					font.pixelSize: Theme.agentPanelLabelSize
				}
			}
		}
	}
}
