import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import "NotifTheme.js" as Theme

// The notification server, and the state everything else draws from.
//
// Quickshell answers org.freedesktop Notifications itself, so this object owning
// a NotificationServer is what makes notifications work -- and it is the only
// thing on the machine that can own that name.
//
// The split of duties: the server tracks
// notifications and the surfaces draw them -- but the *decisions* (do not
// disturb, which notification is newest, when a popup goes away) live here, so
// the popup stack and the control centre cannot disagree with each other.
//
// An Item rather than a QtObject only because NotificationServer and IpcHandler
// need a QObject parent with a default property to sit in. It is never drawn.
Item {
	id: root

	visible: false
	width: 0
	height: 0

	// Emitted when the IPC close-all is asked for, so the panel can run its
	// visual sweep instead of the notifications vanishing in place.
	signal clearAllRequested()

	// ── do not disturb ───────────────────────────────────────────────────────

	// Do not disturb. While this is on, notifications are still tracked and
	// listed in the control centre; they just do not pop up.
	property bool dnd: false

	// Inhibitors: applications that hold DND on while they run.
	// Nothing in the dotfiles uses these, but the client flags exist, so the
	// behaviour does too.
	property var inhibitors: []

	// ── popups ───────────────────────────────────────────────────────────────

	// Notification ids currently drawn as popups, newest first order comes from
	// `popups` below. A popup that times out is deleted from here and the
	// notification stays in `tracked`, and that is why a
	// notification you ignore is still in the panel afterwards.
	property var popping: ({})

	// Mutating a JS object is not observable, so the derived `popups` list
	// reads this counter to know it has to re-evaluate. Every write to `popping`
	// is paired with a bump.
	property int poppingRev: 0

	// The monitor the popups are drawn on, resolved from the focused monitor the
	// moment the stack goes from empty to non-empty, and held until it empties
	// again so that moving the mouse to the other screen does not teleport a
	// popup mid-flight.
	//
	// One monitor only, and it follows focus. Drawing the stack
	// on every monitor also meant every screen armed its own copy of the same
	// timeout, so hovering the popup on one screen left the other screen's timer
	// running, and that timer is what took the popup down mid-hover.
	property string popupMonitor: ""

	// Resolved a turn after the change it follows. Doing it straight from this
	// handler re-entered the popup windows' own bindings -- reading `popups` for
	// the first time is what fires this, and that read happens while
	// `popupMonitor` is being read back -- so QML reported a binding loop.
	onPopupsChanged: Qt.callLater(root.syncPopupMonitor)

	// ── the control centre ───────────────────────────────────────────────────

	property bool centerOpen: false
	// Resolved when the panel opens, so it cannot jump screens while closing.
	property string centerMonitor: ""

	// ── collapsed groups ─────────────────────────────────────────────────────

	// Which app groups the user has opened, by app name: a group is collapsed
	// until it is opened, which is also what the panel measured
	// (three tracked notifications drew one card's worth of height).
	//
	// Kept beside the rest of the state rather than inside the panel, so the
	// panel and the client agree on which groups are open and the client can
	// drive it -- there is no way to click a group from the command line.
	property var expandedGroups: ({})

	function isGroupOpen(app) {
		return root.expandedGroups[app] === true;
	}

	// Replaces the map rather than mutating it, so bindings that read it see the
	// change without a revision counter.
	function setGroupOpen(app, open) {
		var next = ({});
		for (var key in root.expandedGroups)
			if (key !== app)
				next[key] = true;
		if (open)
			next[app] = true;
		root.expandedGroups = next;
		return root.isGroupOpen(app) ? "true" : "false";
	}

	function toggleGroup(app) {
		return root.setGroupOpen(app, !root.isGroupOpen(app));
	}

	// ── derived ──────────────────────────────────────────────────────────────

	readonly property string focusedMonitor: {
		var monitor = Hyprland.focusedMonitor;
		return monitor ? monitor.name : "";
	}

	readonly property bool inhibited: inhibitors.length > 0

	// Every tracked notification, newest first. The server hands them over in
	// arrival order (oldest first), which is why this is reversed.
	readonly property var tracked: {
		var model = server.trackedNotifications;
		var values = model ? model.values : [];
		var out = [];
		for (var i = values.length - 1; i >= 0; i--)
			out.push(values[i]);
		return out;
	}

	readonly property int count: tracked.length

	// The popup stack: the same list, minus everything that has already timed
	// out. Bumped by `poppingRev` so it re-evaluates when `popping` changes.
	readonly property var popups: {
		poppingRev;
		var out = [];
		for (var i = 0; i < tracked.length; i++) {
			var notification = tracked[i];
			if (popping[notification.id] === true)
				out.push(notification);
		}
		return out;
	}

	// ── the server ───────────────────────────────────────────────────────────

	NotificationServer {
		id: server

		// A config edit should not throw the user's notifications away.
		keepOnReload: true

		// Only advertise what the card actually draws. Not advertising body
		// images or markup makes clients send an image hint instead of embedding
		// markup we would have to render.
		bodySupported: true
		bodyMarkupSupported: false
		bodyHyperlinksSupported: false
		bodyImagesSupported: false
		actionsSupported: true
		actionIconsSupported: false
		imageSupported: true
		persistenceSupported: true

		onNotification: (notification) => root.arrive(notification)
	}

	// ── arriving ─────────────────────────────────────────────────────────────

	function arrive(notification) {
		notification.tracked = true;

		// Show a popup for everything except while DND is on. A
		// notification re-emitted by a config reload is already old news.
		if (dnd || notification.lastGeneration)
			return;

		root.popping[notification.id] = true;
		root.poppingRev++;
	}

	// Timeouts are chosen by urgency. A critical
	// notification's timeout is 0, which means "stay until dismissed".
	function timeoutFor(notification) {
		if (notification.urgency === NotificationUrgency.Critical)
			return Theme.timeoutCritical;
		if (notification.urgency === NotificationUrgency.Low)
			return Theme.timeoutLow;
		return Theme.timeoutNormal;
	}

	function hidePopup(notification) {
		delete root.popping[notification.id];
		root.poppingRev++;
	}

	function syncPopupMonitor() {
		if (root.popups.length === 0) {
			root.popupMonitor = "";
			return;
		}

		// Held while the stack is up, so that moving the mouse to another
		// monitor does not teleport a popup mid-flight, but resolved again if
		// the screen it was on has gone away, which is otherwise a popup that
		// nothing can draw.
		if (root.popupMonitor !== "" && root.screenNamed(root.popupMonitor))
			return;

		root.popupMonitor = root.focusedMonitor;
	}

	function screenNamed(name) {
		var screens = Quickshell.screens;
		for (var i = 0; i < screens.length; i++)
			if (screens[i].name === name)
				return true;
		return false;
	}

	// ── what the client asks for ─────────────────────────────────────────────

	// --hide-latest / --hide-all: take the popups down, keep the notifications.
	function hideLatest() {
		if (popups.length > 0)
			hidePopup(popups[0]);
	}

	function hideAll() {
		root.popping = ({});
		root.poppingRev++;
	}

	// --close-latest / -C: actually close them, in the panel too.
	function closeLatest() {
		if (tracked.length > 0)
			tracked[0].dismiss();
	}

	function closeAll() {
		var list = tracked.slice();
		for (var i = 0; i < list.length; i++)
			list[i].dismiss();
	}

	// -a: invoke action `index` of the newest notification; without one, its
	// default action.
	function invokeLatest(index) {
		if (tracked.length === 0)
			return "none";

		var actions = tracked[0].actions || [];
		var chosen = null;

		if (index !== undefined && index !== null && String(index) !== "") {
			var at = parseInt(String(index), 10);
			chosen = (at >= 0 && at < actions.length) ? actions[at] : null;
		} else {
			for (var i = 0; i < actions.length; i++) {
				if (actions[i].identifier === "default") {
					chosen = actions[i];
					break;
				}
			}
			if (chosen === null && actions.length > 0)
				chosen = actions[0];
		}

		if (chosen === null)
			return "none";

		chosen.invoke();
		return "ok";
	}

	// ── the panel ────────────────────────────────────────────────────────────

	function openPanel() {
		root.centerMonitor = root.focusedMonitor;
		root.centerOpen = true;
		// Drop the floating notifications when the centre opens: a
		// popup would otherwise sit on top of the panel it just opened.
		root.hideAll();
	}

	function closePanel() {
		root.centerOpen = false;
	}

	function togglePanel() {
		if (root.centerOpen)
			root.closePanel();
		else
			root.openPanel();
	}

	// ── do not disturb, as the client spells it ──────────────────────────────

	function toggleDnd() {
		root.dnd = !root.dnd;
		return root.dnd ? "true" : "false";
	}

	function getDnd() {
		return root.dnd ? "true" : "false";
	}

	// Accept "true"/"false"; anything truthy enough is taken as on.
	function setDnd(value) {
		var wanted = String(value);
		root.dnd = (wanted === "true" || wanted === "1" || wanted === "on");
		return root.getDnd();
	}

	function getInhibited() {
		return root.inhibited ? "true" : "false";
	}

	function numInhibitors() {
		return String(root.inhibitors.length);
	}

	function addInhibitor(id) {
		var next = root.inhibitors.slice();
		if (next.indexOf(id) < 0)
			next.push(id);
		root.inhibitors = next;
		return root.getInhibited();
	}

	function removeInhibitor(id) {
		root.inhibitors = root.inhibitors.filter((entry) => entry !== id);
		return root.getInhibited();
	}

	function clearInhibitors() {
		root.inhibitors = [];
		return root.getInhibited();
	}

	// The bell's state vocabulary, which is what the bar bell reads.
	// All eight values, covering the combination states: none / notification /
	// dnd-none / dnd-notification / inhibited-none / inhibited-notification /
	// dnd-inhibited-none / dnd-inhibited-notification.
	readonly property string alt: {
		var state = root.count > 0 ? "notification" : "none";
		if (root.dnd && root.inhibited)
			return "dnd-inhibited-" + state;
		if (root.dnd)
			return "dnd-" + state;
		if (root.inhibited)
			return "inhibited-" + state;
		return state;
	}

	// The bar bell's hover tooltip, and the same string the client's `state`
	// reports: the client's state JSON carries a tooltip field, and this is the
	// wording that stands in for it.
	readonly property string tooltip: {
		var text = root.count === 1 ? "1 notification" : (root.count + " notifications");
		if (root.dnd)
			return "Do not disturb" + (root.count > 0 ? " — " + text : "");
		if (root.inhibited)
			return "Inhibited — " + text;
		return text;
	}

	function state() {
		var tooltip = root.count === 1 ? "1 notification" : (root.count + " notifications");
		if (root.dnd)
			tooltip = "Do not disturb" + (root.count > 0 ? " — " + tooltip : "");
		else if (root.inhibited)
			tooltip = "Inhibited — " + tooltip;

		return JSON.stringify({
			"text": root.count > 0 ? String(root.count) : "",
			"alt": root.alt,
			"class": root.alt,
			"tooltip": tooltip
		});
	}

	// ── the client's endpoint ────────────────────────────────────────────────

	IpcHandler {
		target: "notifications"

		// These names are on purpose not `show` (or call/wait/listen/prop):
		// `qs ipc` owns those as subcommands and would swallow the call.
		function panelToggle(): string {
			root.togglePanel();
			return root.centerOpen ? "open" : "closed";
		}

		function panelOpen(): string {
			root.openPanel();
			return "open";
		}

		function panelClose(): string {
			root.closePanel();
			return "closed";
		}

		function dndToggle(): string {
			return root.toggleDnd();
		}

		function dndGet(): string {
			return root.getDnd();
		}

		function dndSet(value: string): string {
			return root.setDnd(value);
		}

		function inhibitedGet(): string {
			return root.getInhibited();
		}

		function inhibitorsCount(): string {
			return root.numInhibitors();
		}

		function inhibitorAdd(id: string): string {
			return root.addInhibitor(id);
		}

		function inhibitorRemove(id: string): string {
			return root.removeInhibitor(id);
		}

		function inhibitorsClear(): string {
			return root.clearInhibitors();
		}

		function notificationCount(): string {
			return String(root.count);
		}

		function groupsState(): string {
			return JSON.stringify(root.expandedGroups);
		}

		function groupToggle(app: string): string {
			return root.toggleGroup(app);
		}

		function groupSetOpen(app: string, open: string): string {
			return root.setGroupOpen(app, open === "true");
		}

		function popupHideLatest(): string {
			root.hideLatest();
			return String(root.popups.length);
		}

		function popupHideAll(): string {
			root.hideAll();
			return "0";
		}

		function closeLatest(): string {
			root.closeLatest();
			return String(root.count);
		}

		function closeAll(): string {
			root.clearAllRequested();
			return "0";
		}

		function action(index: string): string {
			return root.invokeLatest(index);
		}

		function state(): string {
			return root.state();
		}

		// Everything the popup and the panel draw from, for probing.
		function detail(): string {
			var list = [];
			for (var i = 0; i < root.tracked.length; i++) {
				var notification = root.tracked[i];
				list.push({
					"id": notification.id,
					"app": notification.appName,
					"icon": notification.appIcon,
					"summary": notification.summary,
					"body": notification.body,
					"urgency": notification.urgency,
					"actions": (notification.actions || []).length,
					"timeout": root.timeoutFor(notification),
					"popup": root.popping[notification.id] === true
				});
			}
			return JSON.stringify({
				"count": root.count,
				"dnd": root.dnd,
				"alt": root.alt,
				"centerOpen": root.centerOpen,
				"centerMonitor": root.centerMonitor,
				"monitor": root.focusedMonitor,
				"popups": root.popups.length,
				"notifications": list
			});
		}
	}

	// A themed reload hook: apply-wallpaper calls `hayami-notify -rs` after
	// pywal rewrites the palette. BarPalette already watches the file, so this
	// only has to force anything that cached a colour.
	IpcHandler {
		target: "notificationsTheme"

		function reload(): string {
			return "ok";
		}
	}
}
