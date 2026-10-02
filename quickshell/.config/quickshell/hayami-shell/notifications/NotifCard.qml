import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../modules"
import "NotifTheme.js" as Theme
import "NotifActions.js" as Actions

// One notification.
//
// The same card is used twice, because the two contexts are styled
// differently and share the structure:
//
//   popup  .floating-notifications .notification-background: border 2px
//          @border-alt, radius 8, `alpha(@background,.95)`; the inner
//          .notification adds padding 6, and .notification-content margin 14 --
//          20 inside the border. The theme drew a *second* 2px @urgent border
//          inset by 2 when the notification was critical. That is gone: a
//          critical popup now wears the card's own accent outline, the same one
//          the pointer and the keyboard cursor wear, so it is still the only
//          card that reads differently without being the only one drawn twice.
//   centre .control-center .notification-background: the same border and radius,
//          but padding 4 and .notification-content margin 6 padding 4/6/2/2 --
//          10 inside the border, and no critical marker of any kind (the theme
//          tinted the whole card there, and that tint was never ported).
//
// Both share `.notification > *:last-child > * { min-height: 3.4em }`, which is
// what makes a text-only card the height it is: measured 93 tall with no icon,
// against 112 with a 48px one, which is exactly 2*2 + 2*(20 + max(47.6, 48+20)).
Item {
	id: card

	required property var notification
	required property var notifColors
	// The NotifState this card belongs to. Only used for popups, which need it
	// for their dwell timeout and to take themselves down.
	property var state: null
	// Popup (floating, self-expiring) vs control-centre row.
	property bool popup: false
	// The panel's keyboard cursor is on this card: the card's whole border takes
	// the panel's accent colour (see NotifTheme.js for why it is an outline
	// rather than the launcher's bar down the left edge).
	property bool keyFocused: false
	// This card is the front of a collapsed group, so a click on it opens the
	// group instead of running the notification's default action: in a stack the
	// click means "show me the rest of them".
	property bool expandOnClick: false

	signal expandRequested()

	// A panel sweep pins the list's model, so a delegate can outlive its
	// notification -- the wrapper is destroyed the moment it is dismissed,
	// while the card still exists. Bindings must not read a null.
	readonly property var n: notification

	readonly property bool critical: n ? n.urgency === NotificationUrgency.Critical : false

	// Whether this card shows the critical marker, which is popups only. The
	// centre has never carried one: the theme it came from tinted the whole
	// card there, and that tint was never ported, so a critical notification in
	// the panel is marked by nothing. Deliberately left that way rather than
	// fixed here -- it is a change to how panel rows read, and this is about
	// the popups.
	readonly property bool criticalPopup: card.popup && card.critical

	// Paused while the pointer is over the card, so a notification you are
	// reading does not vanish.
	readonly property bool hovered: hover.hovered

	// The card is showing its outline cue: the panel's keyboard cursor is on it,
	// the pointer is over it, or it is a critical popup. All three take the same
	// border -- the accent colour, at the focus weight -- so "this needs you"
	// looks like one thing wherever it comes from. There used to be a fourth
	// look for critical: a second 2px @urgent ring drawn inside the border,
	// which made an urgent popup the only card in the stack wearing two
	// outlines and read as a rendering fault rather than as a priority.
	//
	// Hover is not conditioned on the card being clickable, nor on it being a
	// panel card: a popup answers the pointer the same way. Being pointable is
	// what the outline describes, and a notification with no default action is
	// still something the pointer is on.
	readonly property bool outlined: keyFocused || hovered || criticalPopup

	// The inset from the card's own border to its content. The two variants
	// differ, and the centre's is not even symmetric -- see NotifTheme.js for
	// where each number comes from.
	readonly property int padTop: popup ? Theme.popupPad : Theme.centerPadTop
	readonly property int padBottom: popup ? Theme.popupPad : Theme.centerPadBottom
	// Horizontally the centre's .notification-content also carries `padding: 0
	// 6px`, which is left out here: it only shifts the text 4px sideways.
	readonly property int padSide: popup ? Theme.popupPad : Theme.centerPadSide

	// .close-button { margin: 6px; padding: 2px } in a popup, but
	// `margin: 0; padding: 4px` in the centre.
	readonly property int closeInset: popup ? Theme.closeMargin : 0
	readonly property int closePad: popup ? 2 : 4

	// The icon: the image hint, else the app icon resolved through the theme,
	// else nothing. A notification with no icon draws no icon at all rather
	// than a placeholder, and it is why the card is
	// 20px shorter in that case.
	readonly property string iconSource: {
		if (!n)
			return "";

		var image = n.image;
		if (image)
			return image;

		var name = n.appIcon;
		if (name) {
			if (name.indexOf("/") === 0 || name.indexOf("file://") === 0)
				return name;
			var path = Quickshell.iconPath(name, true);
			if (path)
				return path;
			// Some clients put the desktop file's name in app_icon.
			path = Quickshell.iconPath(name.replace(/\.desktop$/, ""), true);
			if (path)
				return path;
		}

		var entry = n.desktopEntry;
		if (entry) {
			var fromEntry = Quickshell.iconPath(entry.replace(/\.desktop$/, ""), true);
			if (fromEntry)
				return fromEntry;
		}

		// Last resort: the app name itself, which is often the icon name
		// (e.g. "Spotify").
		if (n.appName) {
			var byApp = Quickshell.iconPath(n.appName.toLowerCase(), true);
			if (byApp)
				return byApp;
		}

		return "";
	}

	readonly property var actions: n ? (n.actions ? n.actions : []) : []

	// The action a click on the card runs, and the whole card is the target --
	// there are no action buttons drawn anywhere now, on either surface.
	//
	// Which action counts as "the" one is NotifActions.js's business, because
	// the panel's cursor and the command line have to answer the same question
	// the same way -- and used to answer it differently.
	readonly property var primaryAction: Actions.pick(card.actions)

	readonly property bool clickable: expandOnClick || primaryAction !== null

	implicitWidth: 200
	implicitHeight: frame.height

	// ── dragging a card away ───────────────────────────────────────────────
	// Pull a card far enough to either side and letting go closes it. The panel's cards do the same thing now; in the
	// panel's list a *vertical* drag stays the list's own scroll (the handler is
	// x-axis only), and a notification can still be dismissed with a key or the
	// close button.
	//
	// The card is *translated* rather than moved: the popup stack's slide-in
	// animation owns `x`, a Column owns the panel rows', and a transform touches
	// neither. The card fades out as it is pulled: it is fully transparent by
	// the dismiss distance, which the popup surface's drag room leaves
	// comfortably inside its left edge (see Theme.popupDragRoom); the panel's
	// list is clipped, so a card there slides out under the list edge.
	property bool draggable: true
	property real dragX: 0
	property bool flying: false
	// The sweep's programmatic exits fade through here: `exitFades` switches
	// the opacity over to `flyOpacity` so a cascade can fade the card on its
	// own curve without touching the drag-driven fade a manual swipe uses.
	property bool exitFades: false
	property real flyOpacity: 1
	// The notification this card is flying out on behalf of, held at the
	// moment the flight starts: the group's model can shift mid-flight (a new
	// notification re-fills the front card), and the dismissal must take the
	// one that was swiped, never the one that replaced it.
	property var dismissing: null
	readonly property real dragDistance: Math.max(Theme.dragMinDistance, card.width * Theme.dragDismissFraction)
	readonly property real dragProgress: Math.min(1, Math.abs(card.dragX) / card.dragDistance)

	transform: Translate {
		x: card.dragX
	}

	DragHandler {
		id: drag

		enabled: card.draggable
		target: null
		yAxis.enabled: false

		onActiveTranslationChanged: {
			if (drag.active)
				card.dragX = drag.activeTranslation.x;
		}

	onActiveChanged: {
		if (drag.active || card.flying)
			return;

		if (Math.abs(card.dragX) >= card.dragDistance)
			card.flyAway();
		else
			settle.restart();
	}
}

	// Let go short of the threshold and the card goes back where it was.
	NumberAnimation {
		id: settle

		target: card
		property: "dragX"
		to: 0
		duration: Theme.transition
		easing.type: Easing.OutCubic
	}

	// Past it, the rest of the way off, and then close the notification for real
	// -- `dismiss()` rather than `state.hidePopup()`, so a swipe takes it out of
	// the panel too. The target is the one captured at launch, not whatever the
	// card shows by the time the flight lands.
	NumberAnimation {
		id: exit

		target: card
		property: "dragX"
		duration: Theme.transition
		easing.type: Easing.OutCubic

		onStopped: {
			if (card.flying && card.dismissing) {
				try {
					card.dismissing.dismiss();
				} catch (e) {
				}
				card.dismissing = null;
			}
		}
	}

	// The sweep's flight: same curve as `exit`, no dismissal attached.
	NumberAnimation {
		id: quiet

		target: card
		property: "dragX"
		duration: Theme.transition
		easing.type: Easing.OutCubic

		onStopped: {
			if (card.exitFades) {
				card.flying = false;
				if (card.dismissing) {
					try {
						card.dismissing.dismiss();
					} catch (e) {
					}
					card.dismissing = null;
				}
			}
		}
	}

	// Its fade, riding the same curve so the card melts as it slides.
	NumberAnimation {
		id: fade

		target: card
		property: "flyOpacity"
		to: 0
		duration: Theme.transition
		easing.type: Easing.OutCubic
	}

	// `direction` is -1 (left) or 1 (right); a swipe derives it from the drag,
	// a programmatic delete passes one so the exit is always the same way.
	function flyAway(direction) {
		var dir = (direction === -1 || direction === 1) ? direction
			: (card.dragX < 0 ? -1 : 1);
		card.flying = true;
		card.dismissing = card.notification;
		exit.to = dir * (card.width + Theme.dragExitOvershoot);
		exit.restart();
	}

	// The programmatic exit: the same flight a swipe gets -- slide, fade,
	// same curve -- but at full duration for both, so the card visibly
	// travels and melts instead of popping past the drag threshold. The
	// dismissal rides the flight's end when the caller set `dismissing`.
	// dragX is left at the flight's end (off-window, faded to nothing)
	// because the card still exists in the model until the dismissal lands;
	// resetting it would snap it back into view.
	function flyOut(direction) {
		var dir = (direction === 1 || direction === -1) ? direction : 1;
		card.flying = true;
		card.exitFades = true;
		settle.stop();
		quiet.to = dir * (card.width + Theme.dragExitOvershoot);
		quiet.restart();
		fade.restart();
	}

	// The model re-filling this card (the group's front card takes the next
	// notification after the one before it was taken away) ends any flight in
	// progress: the card lands back where it belongs and nothing behind it is
	// dismissed by mistake.
	function cancelFlight() {
		card.flying = false;
		card.dismissing = null;
		card.exitFades = false;
		card.flyOpacity = 1;
		card.dragX = 0;
		exit.stop();
		settle.stop();
		quiet.stop();
		fade.stop();
	}

	// A popup takes itself down after its urgency's timeout. A critical
	// notification's timeout is 0, which means it stays.
	//
	// Armed and disarmed from `armDwell` rather than with a
	// `running: ... && !card.hovered` binding, so that hovering stops the
	// countdown outright and un-hovering gives the popup its full timeout again.
	Timer {
		id: dwell

		interval: (card.popup && card.state && card.n) ? card.state.timeoutFor(card.n) : 0

		onIntervalChanged: card.armDwell()
		onTriggered: {
			// The wrapper can be destroyed between arming and firing (a
			// sweep dismissed the notification under this popup).
			if (card.n)
				card.state.hidePopup(card.n);
		}
	}

	// Restarts the whole timeout on un-hover: the
	// popup gets its full five seconds again rather than the remainder.
	function armDwell() {
		dwell.stop();

		if (dwell.interval > 0 && card.popup && card.state !== null && !card.hovered)
			dwell.start();
	}

	Component.onCompleted: card.armDwell()
	onHoveredChanged: card.armDwell()

	Rectangle {
		id: frame

		width: card.width
		height: layout.implicitHeight + card.padTop + card.padBottom + Theme.cardBorderWidth * 2

		radius: Theme.cardRadius
		// Hovering thickens a card's outline to the accent border the keyboard
		// cursor draws, because the whole card is the click target and has to
		// look like one. It used to tint the whole card instead, but the tint is
		// translucent and let the cards behind a stacked group show straight
		// through it. A popup outlines on hover too; its close button fading in
		// stays as the extra cue for the one control on it.
		//
		// The opacity is the drag: a popup being pulled away fades as it goes.
		// A sweep exit swaps that for its own fade so the two never fight.
		opacity: card.exitFades ? card.flyOpacity : (1 - card.dragProgress)
		color: card.notifColors.cardBackground
		// At rest the outline is the section-border weight, so a card sits in the
		// panel at the same weight as the grid buttons and the boxes around the
		// volume and media sections; the cursor or the pointer takes it up a step
		// to focusBorderWidth, which is the leap every other section makes. Only
		// the drawn width changes -- the indent the content is placed at is still
		// cardBorderWidth, so nothing shifts when the outline thickens.
		border.width: card.outlined ? Theme.focusBorderWidth : Theme.controlBorderWidth
		border.color: card.outlined ? card.notifColors.selected : card.notifColors.border

		ColumnLayout {
			id: layout

			x: card.padSide + Theme.cardBorderWidth
			y: card.padTop + Theme.cardBorderWidth
			width: frame.width - (card.padSide + Theme.cardBorderWidth) * 2
			spacing: 0

			// ── icon + text ──────────────────────────────────────────────────
			RowLayout {
				Layout.fillWidth: true
				Layout.minimumHeight: Theme.contentMinHeight
				spacing: 0

				Image {
					visible: card.iconSource !== ""
					Layout.preferredWidth: Theme.iconSize
					Layout.preferredHeight: Theme.iconSize
					Layout.alignment: Qt.AlignTop
					Layout.topMargin: Theme.iconMarginTop
					Layout.bottomMargin: Theme.iconMarginBottom
					Layout.rightMargin: Theme.iconMarginRight
					source: card.iconSource
					sourceSize.width: Theme.iconSize
					sourceSize.height: Theme.iconSize
					fillMode: Image.PreserveAspectFit
					smooth: true
				}

				ColumnLayout {
					Layout.fillWidth: true
					Layout.alignment: Qt.AlignVCenter
					spacing: 2

					Text {
						id: summary

						Layout.fillWidth: true
						text: card.n ? card.n.summary : ""
						textFormat: Text.PlainText
						wrapMode: Text.WordWrap
						font.family: Theme.fontFamily
						font.pixelSize: Theme.fontSize
						font.weight: Theme.summaryWeight
						color: card.notifColors.text
					}

					Text {
						Layout.fillWidth: true
						visible: text !== ""
						text: card.n ? card.n.body : ""
						textFormat: Text.PlainText
						wrapMode: Text.WordWrap
						font.family: Theme.fontFamily
						font.pixelSize: Theme.bodySize
						color: card.notifColors.text
						opacity: 0.85
					}
				}
			}

			// ── no action buttons ────────────────────────────────────────────
			// There used to be a row of them here, drawn for popups only. They
			// are gone from both surfaces now, and the card is the whole target:
			// `bodyArea` below runs `primaryAction`, so the action is still
			// reachable -- it is just the card that reaches it, rather than a
			// labelled pill in the corner of it.
			//
			// What that buys is that a card looks like a card. The row was the
			// only thing that made an actionable notification a different shape
			// from one that merely had text in it, so the same notification was
			// drawn two different heights depending on what the sending app
			// happened to offer -- and the taller version is what arrived in the
			// corner, where it pushes the rest of the stack down.
		}

		// ── the close button ─────────────────────────────────────────────────
		// style.css: .close-button { margin: 6px; padding: 2px; border-radius: 6px }
		// inside the notification's 2px border.
		Rectangle {
			id: closeButton

			width: Theme.closeSize + card.closePad
			height: Theme.closeSize + card.closePad
			x: frame.width - width - (Theme.cardBorderWidth + card.closeInset)
			y: Theme.cardBorderWidth + card.closeInset
			radius: Theme.closeRadius
			color: closeArea.containsMouse ? card.notifColors.selected : "transparent"
			// The close button is only revealed while the notification is
			// hovered -- measured off a live un-hovered popup, which has no ink
			// anywhere in the button's corner.
			opacity: card.hovered ? 1 : 0

			Behavior on opacity {
				NumberAnimation {
					duration: Theme.transition
				}
			}

			SymbolicIcon {
				anchors.fill: parent
				anchors.margins: 4
				source: Quickshell.iconPath("window-close-symbolic", true)
				color: card.notifColors.text
			}

			MouseArea {
				id: closeArea

				anchors.fill: parent
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				onClicked: {
					card.dismissing = card.notification;
					card.flyOut(1);
				}
			}
		}

		// ── clicking the body runs the default action ────────────────────────
		// Declared before the action buttons and the close button in the child
		// order that matters (it is the *first* child here, so it sits under
		// them and they win the click).
		MouseArea {
			id: bodyArea

			anchors.fill: parent
			z: -1
			acceptedButtons: Qt.LeftButton
			cursorShape: card.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
			onClicked: {
				if (card.expandOnClick)
					card.expandRequested();
				else if (card.primaryAction)
					card.primaryAction.invoke();
			}
		}

	}

	HoverHandler {
		id: hover
	}
}
