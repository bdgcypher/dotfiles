import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons
import "Theme.js" as Theme

// custom/agent -- the freebuff coding agent.
//
// Two things this module is for, and they are different: the glyph says whether
// an agent session is running at all, which is the one thing worth knowing from
// across the room, and the popout answers the questions a 26px strip cannot hold
// -- which model, which project, how long, and what it is costing. The glyph
// answers the first question about *any* of them; when several sessions are live
// the popout is what says which is which.
//
// It is one module and not a readout for a reason: the reading comes from
// scripts/agent-status.sh, which is where the local session file and the
// Freebucks API are merged. Read here and handed to the panel, rather than
// probed twice, so the icon and the panel can never disagree -- the same
// arrangement the VPN indicator and its panel use.
//
// The module never collapses the way Voxtype and the recording indicator do: a
// module that vanished while the agent was idle would leave SUPER+A with nothing
// to anchor a panel to. Idle is dimmed instead, which also reads as the honest
// state -- the agent is installed and not doing anything.
BarItem {
	id: root

	// The shell's bar state, so the click and the keybind reach the same flag
	// (BarState.agentPanel) instead of each keeping its own idea of whether the
	// panel is up.
	property var state: null

	// The screen this bar is on, so the panel opens on the same monitor.
	property var screenModel: null

	// Whether this is the bar on the monitor with the focus. The panel is one
	// shared flag but only one monitor may draw it, or SUPER+A would open a card
	// on every screen at once. Assigned by Bar.qml, which already works this out
	// for the bar's keyboard mode.
	property bool focused: false

	// ── the reading ──────────────────────────────────────────────────────────
	//
	// What agent-status.sh last said. Every field defaults to the idle/no-wallet
	// shape, so a shell that has not had its first probe yet draws the idle glyph
	// rather than an error.

	property bool live: false

	// Which agent the reading is about, as agent-status.sh spells it. It comes
	// from the script rather than being written here, so the card's subheading
	// and the window `hayami-agent new` opens are the same word -- and so
	// swapping agents is a change to the one script that already knows what a
	// session is.
	property string provider: ""

	// Every live session, in the order the script read them. An agent is known by
	// the directory it is working in, and there can be more than one at once, so
	// this is a list and not the one model/project pair it used to be -- the panel
	// is what tells them apart.
	property var sessions: []

	// How many that is, for the glyph's own count.
	readonly property int count: sessions.length

	// The badge's two states, as the script sees them: `working` is a run in
	// progress, `finished` a turn over and waiting to be read. The script decides
	// both (see agent-status.sh) so the module never has to guess at either from
	// timing.
	property bool finished: false
	property bool working: false

	// Which of them the badge is reporting. One glyph stands for every session,
	// so this is the most urgent state any of them is in, not a count. A live run
	// outranks a finished one because it is the state still moving. "none" is the
	// idle shell, which wears no badge at all.
	readonly property string badgeState: working ? "working"
		: finished ? "finished"
		: "none"

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
	property string tooltipLine: ""

	// The cluster's margin either side, so it slots into the status row at the
	// same spacing as its neighbours.
	marginLeft: 6
	marginRight: 6

	glyph: Icons.agent

	// A count on the bar itself once there is more than one session. The glyph
	// says an agent is running; only a number says how many, and the session
	// file it would otherwise take to find out is three clicks away. One session
	// keeps the plain glyph -- that is the ordinary case, and a "1" beside the
	// icon would be noise next to the dozen other modules -- while the tooltip
	// lists them by directory either way.
	//
	// It rides the module's own reading: on a horizontal bar that is the digit
	// beside the glyph, and on a vertical one it is the line under it, which is
	// where a vertical bar puts every module's value.
	suffix: count > 1 ? " " + count : ""

	// The badge, on the same terms as the notification bell's -- same dot, same
	// slot -- but saying which of the three states it is rather than only that
	// something wants you. The panel's list is where the answer to "which one"
	// is; the colour here is the answer to "how badly".
	dot: badgeState !== "none"// The badge's colour, set with a Binding rather than by redeclaring
		// BarItem's own dotColor: a redeclaration of an inherited property does not
		// take here, and the badge silently keeps the base's alert default -- a red
		// dot on every state.
		//
		// Green for a run under way, a flat gray for a turn that is merely over.
		// Both are fixed roles rather than pywal's, so no wallpaper can repaint one
		// state as the other.
		Binding {
			target: root
			property: "dotColor"
			value: !root.pal ? "#7a8085"
				: root.badgeState === "working" ? root.pal.working
				: root.pal.finished
		}

	tooltipText: tooltipLine

	// No colour of its own: the glyph is drawn in the bar's base foreground,
	// the way most of the modules are, and the two states are told apart by
	// strength rather than by hue -- full while a session is live, dimmed to
	// near-grey while it is not. That is the shell's own way of saying "not
	// doing anything" (the tiling direction and the workspaces do the same),
	// and it suits a module that spends most of its time idle: an accent would
	// spend itself on a glyph that is almost never running, and would leave the
	// count beside it competing with the module's own reading.
	dim: live ? 1.0 : 0.45

	// The module's own corner inside the bar's surface, and how much of the bar
	// it takes up there, so the panel centres on the module rather than hanging
	// off its leading edge -- the same sum VpnIndicator makes, and for the same
	// reason (see its comment).
	readonly property point agentAnchor: Qt.point(
		(vertical ? 0 : Theme.sectionPadding) + parent.x + x,
		(vertical ? Theme.sectionPadding : 0) + parent.y + y)
	readonly property size agentAnchorSize: Qt.size(width, height)

	onClicked: if (root.state)
		root.state.toggleAgentPanel()

	function refresh() {
		if (!probe.running)
			probe.running = true
	}

	// The panel is this module's child, not the bar's: it anchors to where the
	// indicator is, and it closes with the module that owns it when the agent
	// module is switched off in the launcher's Bar -> Toggle menu.
	AgentPanel {
		id: panel

		pal: root.pal
		edge: root.edge
		screenModel: root.screenModel
		anchor: root.agentAnchor
		anchorSize: root.agentAnchorSize

		live: root.live
		provider: root.provider
		sessions: root.sessions
		loggedIn: root.loggedIn
		balance: root.balance
		dailyLimit: root.dailyLimit
		dailySpent: root.dailySpent
		dailyRemaining: root.dailyRemaining
		dailyResetAt: root.dailyResetAt
		wallet: root.wallet
		tier: root.tier
		streak: root.streak
		note: root.note

		// The shared flag, narrowed to the monitor that may draw it: the card
		// belongs to the bar the keyboard is on, so exactly one screen shows it.
		open: root.state ? (root.state.agentPanel && root.focused) : false

		// Escape and a click off the card come back here rather than writing the
		// flag themselves, so the bar state stays the one owner of it.
		onDismissed: if (root.state)
			root.state.setAgentPanel(false)

		// A new session, from the card's own row. The panel emits and this runs
		// the command, for the same reason it does not write the flag itself:
		// the card draws and asks, and this module is what reaches the rest of
		// the system.
		//
		// The card goes down *first*. It holds the keyboard exclusively while it
		// is up, and the terminal it opens would map underneath a card that has
		// the keyboard -- a window you cannot type into.
		onLaunchRequested: {
			if (root.state)
				root.state.setAgentPanel(false)
			launcher.running = true
		}
	}

	// `hayami agent new`, which is what the SUPER+SHIFT+A bind runs, called on
	// the script behind the dispatcher rather than through it: one command
	// either way, and no dependency on the dispatcher's own argument parsing.
	// It backgrounds the terminal itself, so this exits as soon as it has
	// spawned it.
	Process {
		id: launcher

		command: ["hayami-agent", "new"]
	}

	Process {
		id: probe

		command: ["bash", Quickshell.env("HOME")
			+ "/.config/quickshell/hayami-shell/scripts/agent-status.sh"]

		// Nothing is blanked on start: unlike the VPN glyph, the idle reading is
		// a real state rather than the absence of one, and clearing it every five
		// seconds would make the module flicker between live and idle.
		stdout: SplitParser {
			onRead: function(line) {
				var data = null;
				try {
					data = JSON.parse(line);
				} catch (e) {
					return;
				}
				if (!data)
					return;
				root.live = data.live === true;
				root.provider = data.provider ? String(data.provider) : "";
			root.finished = data.anyFinished === true;
				root.working = data.anyWorking === true;
				// Read as an array or not at all: the panel iterates this, and a
				// payload that arrived without one must not empty the list.
				root.sessions = Array.isArray(data.sessions) ? data.sessions : [];
				root.loggedIn = data.loggedIn === true;
				root.balance = Number(data.balance) || 0;
				root.dailyLimit = Number(data.dailyLimit) || 0;
				root.dailySpent = Number(data.dailySpent) || 0;
				root.dailyRemaining = Number(data.dailyRemaining) || 0;
				root.dailyResetAt = data.dailyResetAt ? String(data.dailyResetAt) : "";
				root.wallet = Number(data.wallet) || 0;
				root.tier = data.tier ? String(data.tier) : "";
				root.streak = Number(data.streak) || 0;
				root.note = data.note ? String(data.note) : "";
				root.tooltipLine = data.tooltip ? String(data.tooltip) : "";
			}
		}
	}

	// style.css has no interval for this module; five seconds is what the VPN
	// indicator uses. It costs nothing to run this often: the script only reaches
	// the network when its own cache has expired.
	Timer {
		interval: 5000
		running: true
		repeat: true

		onTriggered: root.refresh()
	}

	Component.onCompleted: root.refresh()
}
