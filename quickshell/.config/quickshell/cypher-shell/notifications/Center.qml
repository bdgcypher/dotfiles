import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../modules"
import "NotifTheme.js" as Theme

// The control centre -- swaync's panel.
//
// Geometry, all measured off the live swaync window on this 1.1-scaled screen
// (`hyprctl layers -j` plus grim crops of the @color6 border):
//
//   card     408 wide (380 + 2*12 padding + 2*2 border) and 879 tall
//   edges    right edge 25 from the screen edge, 52 from the top, 51 from the
//            bottom -- that is the config's control-center-margin-top/bottom 2
//            and margin-right 1, plus central_control.css's `margin: 50px 24px`
//   window   432 wide (the card plus its 24px right margin), full height
//
// The window is full screen rather than 432 wide so that a click anywhere
// outside the card can close the panel: swaync gets that for free from the
// compositor by grabbing keyboard focus and quitting on focus loss, and a
// full-surface click target is the same behaviour without depending on focus
// events. It is transparent, on the top layer, so it sits over the bar -- which
// is what makes clicking the bar close the panel instead of hitting the bar.
PanelWindow {
	id: root

	required property var modelData
	required property var state
	required property var pal

	screen: modelData

	// Whether this is the screen the panel belongs to.
	//
	// Compared against the screen this instance was built for rather than the
	// window's own `screen`: the latter is managed by the shell, so reading it
	// here fed a change straight back into this binding, which QML reported as a
	// binding loop on `open` -- and a property caught in a loop can be left
	// stale, which is the flag that decides whether the panel is visible at all.
	readonly property bool open: state.centerOpen
		&& (modelData ? modelData.name === state.centerMonitor : false)

	visible: open

	// The panel opens with nothing under the cursor, so the first vertical key is
	// what puts it on the first body button rather than starting it halfway down.
	// The cursor stops with the panel: the surface does not hold the keyboard
	// while it is hidden, so a stale cursor would sit there outlined with nothing
	// to navigate.
	// Whether notifications are shown (the inverse of DND), so the switch in the
	// title row can read as notifications on/off. Lives on the root because QML
	// resolves unqualified names through ids and the component root only -- a
	// property on an intermediate Item is invisible to its grandchildren, which
	// silently froze every binding that pointed at it.
	readonly property bool notificationsOn: !state.dnd

	onOpenChanged: {
		if (root.open) {
			root.focusGroup = 0;
			root.focusItem = 0;
			root.setStop("");
		} else {
			root.stopName = "";
			root.focusActive = false;
		}
	}

	onNotificationGroupsChanged: Qt.callLater(root.clampFocus)

	// A player or the backlight can come and go while the panel is open, which
	// adds a stop or takes one away. If the cursor was on it, it lands on the
	// list rather than on whatever has slid into that position since.
	onStopsChanged: {
		if (root.stopName !== "" && root.stops.indexOf(root.stopName) < 0)
			root.setStop("list");
	}

	anchors {
		top: true
		right: true
		bottom: true
		left: true
	}

	margins {
		top: Theme.centerMarginTop
		bottom: Theme.centerMarginBottom
		right: Theme.centerMarginRight
	}

	// Never grab the keyboard while the panel is hidden, or the surface would
	// hold the session's input after a close.
	exclusiveZone: 0
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Top
	WlrLayershell.namespace: "quickshell:notifications-center"
	WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

	NotifColors {
		id: colors

		pal: root.pal
	}

	// ── clicking outside the card closes the panel ───────────────────────────
	MouseArea {
		anchors.fill: parent
		onClicked: root.state.closePanel()
	}

	// ── keyboard ─────────────────────────────────────────────────────────────

	// config.json: "keyboard-shortcuts": true. The panel holds the keyboard for
	// as long as it is open, so every key the shortcuts use arrives here.
	//
	// One cursor walks the panel, from the button grid at the top to the last
	// notification at the bottom. `stops` is the order it walks them in; handleKey
	// is what the keys mean once it is there.
	FocusScope {
		id: keys

		anchors.fill: parent
		focus: root.open

		Keys.onPressed: (event) => {
			if (event.key === Qt.Key_Escape) {
				root.state.closePanel();
			} else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
				// Tab used to step between the sections; the single cursor covers
				// them now, so the key is swallowed rather than handed to focus
				// traversal.
			} else if (!root.handleKey(event)) {
				return;
			}

			event.accepted = true;
		}
	}

	// ── the card ─────────────────────────────────────────────────────────────
	Rectangle {
		id: card

		anchors.top: parent.top
		anchors.bottom: parent.bottom
		anchors.right: parent.right
		anchors.topMargin: Theme.centerCardMarginTop
		anchors.bottomMargin: Theme.centerCardMarginBottom
		anchors.rightMargin: Theme.centerCardMarginRight
		width: Theme.centerCardWidth

		radius: Theme.cardRadius
		color: colors.cardBackground
		border.width: 2
		border.color: colors.border

		// The panel is a fixed height (the screen less its margins), so the
		// notification list is what absorbs the slack -- swaync's list scrolls
		// for exactly this reason.
		ColumnLayout {
			id: layout

			anchors.fill: parent
			anchors.margins: Theme.centerCardPadding + 2
			spacing: 0

			// config.json widget order: label, buttons-grid, volume, mpris, title,
			// dnd, notifications -- less the empty label widget at the head of it,
			// and less dnd, whose switch now rides in the title row.
			// It was 22px of nothing above the buttons, which is what made the top
			// inset 42 where the sides use 20; without it the card's padding plus
			// the grid's own margin spaces the top exactly as they space the sides.
			CenterGrid {
				id: grid

				Layout.fillWidth: true
				// .widget-buttons-grid { margin: 6px }: the sides and the top keep
				// swaync's own margin -- that is what makes the panel's top inset
				// match its sides. The space below it is a section gap instead.
				Layout.leftMargin: Theme.gridMargin
				Layout.rightMargin: Theme.gridMargin
				Layout.topMargin: Theme.gridMargin
				Layout.bottomMargin: 0
				notifColors: colors
				sectionFocused: root.stopIs("grid")
			}

			CenterVolume {
				id: volume

				Layout.fillWidth: true
				Layout.leftMargin: Theme.volumeMargin
				Layout.rightMargin: Theme.volumeMargin
				// .widget-volume { margin: 6px } sets all four; the vertical space
				// around a section is Theme.centerSectionGap, not this.
				Layout.topMargin: Theme.centerSectionGap
				Layout.bottomMargin: 0
				notifColors: colors
				// Volume and brightness are two stops of their own, so the section is
				// told which knob the cursor is on rather than that it is on the
				// section at all.
				focusedRow: root.stopIs("volume") ? 0 : (root.stopIs("brightness") ? 1 : -1)
				// The backlight is only polled while the panel is up.
				poll: root.open
			}

			CenterMpris {
				id: mpris

				Layout.fillWidth: true
				Layout.leftMargin: Theme.mprisMargin
				Layout.rightMargin: Theme.mprisMargin
				// .widget-mpris { margin: 20px 6px }'s 20px is not kept: it made
				// this the widest gap in the panel by a distance no other section had.
				Layout.topMargin: Theme.centerSectionGap
				Layout.bottomMargin: 0
				notifColors: colors
				sectionFocused: root.stopIs("mpris")
			}

			// ── title: "Notifications" + DND + clear all ─────────────────────
			Item {
				Layout.fillWidth: true
				Layout.leftMargin: Theme.titleMargin
				Layout.rightMargin: Theme.titleMargin
				// Above the heading is a section gap; below it stays the
				// notification section's own, tuned separately.
				Layout.topMargin: Theme.centerSectionGap
				Layout.bottomMargin: Theme.titleMarginVertical
				// The DND switch's ring is the only child taller than the control
				// it wraps, so it is measured too.
				implicitHeight: Math.max(titleLabel.implicitHeight, clearButton.height, dndRing.height)

				Text {
					id: titleLabel

					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					text: Theme.titleText
					font.family: Theme.fontFamily
					font.pixelSize: Theme.titleSize
					font.weight: Theme.titleWeight
					color: colors.text
				}

				// Do not disturb, moved up out of a row of its own: it sat under a
				// "Do not disturb" caption, and with the caption gone the switch
				// belongs with the row's other control rather than beside nothing.
				// To the left of clear-all, the title row's right end.
				//
				// The switch reads as notifications on/off rather than DND: the
				// "on" end -- knob right, accent fill -- is the state notifications
				// are shown, and DND slides the knob left and greys the track. That
				// keeps this control pointing the same way as everything else in
				// the row.
				Rectangle {
					id: dndSwitch

					anchors.right: clearButton.left
					anchors.rightMargin: Theme.titleControlGap
					anchors.verticalCenter: parent.verticalCenter
					width: Theme.dndSwitchWidth
					height: dndSwitchSlider.height + Theme.dndSwitchPadding * 2
					radius: height / 2
					color: notificationsOn
						? (dndArea.containsMouse ? colors.hoverAlt : colors.selected)
						: (dndArea.containsMouse ? colors.hoverAlt : colors.backgroundAlt)

					Rectangle {
						id: dndSwitchSlider

						width: Theme.dndSwitchWidth / 2 - Theme.dndSwitchPadding
						height: width
						radius: width / 2
						color: colors.text
						y: Theme.dndSwitchPadding
						x: notificationsOn
							? Theme.dndSwitchWidth - width - Theme.dndSwitchPadding
							: Theme.dndSwitchPadding

						Behavior on x {
							NumberAnimation {
								duration: Theme.transition
								easing.type: Easing.OutCubic
							}
						}
					}

					MouseArea {
						id: dndArea

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.state.toggleDnd()
					}
				}

				// A ring rather than a border on the switch itself: the switch already
				// wears the accent fill when DND is on, so a border in that colour
				// would vanish exactly when the cursor is on it.
				Rectangle {
					id: dndRing

					anchors.fill: dndSwitch
					anchors.margins: -(Theme.focusBorderWidth + 1)
					radius: height / 2
					visible: root.stopIs("title") && root.titleControl === 0
					color: "transparent"
					border.width: Theme.focusBorderWidth
					border.color: colors.selected
				}

				Rectangle {
					id: clearButton

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					// Three times its height -- the height is the switch's, so the two
					// controls match and the width is a plain multiple of it.
					width: height * Theme.titleButtonAspect
					// The switch's height, not the label's line box plus padding: the
					// two controls share the row's right end, so the shorter one sets
					// the height and the glyph centres in what is left (measured 20
					// against the label's 19).
					height: dndSwitch.height
					radius: Theme.cardRadius
					color: clearArea.containsMouse ? colors.hoverAlt : colors.backgroundAlt
					// The button's own fill is too close to the card's for a tint to
					// read, so the cursor is the ring.
					border.width: (root.stopIs("title") && root.titleControl === 1) ? Theme.focusBorderWidth : 0
					border.color: colors.selected

					Text {
						id: clearLabel

						anchors.centerIn: parent
						text: Theme.titleClearGlyph
						font.family: Theme.fontFamily
						font.pixelSize: Theme.fontSize
						color: colors.text
					}

					MouseArea {
						id: clearArea

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.dismissAllVisually()
					}
				}
			}

			// ── the notification list ────────────────────────────────────────
			Flickable {
				id: list
				Layout.fillWidth: true
				Layout.fillHeight: !emptyState.visible
				// The list's own 2px margin, plus the air between the title row and
				// the first card.
				Layout.topMargin: Theme.groupMargin + Theme.centerListTopGap
				contentHeight: groups.implicitHeight
				clip: true
				boundsBehavior: Flickable.StopAtBounds

				Column {
					id: groups

					width: list.width
					spacing: Theme.centerGroupGap

					Repeater {
						id: groupRepeater
						// Pinned during a sweep so cards stay alive mid-flight.
					model: root.sweepActive ? modelPrevious : root.notificationGroups

						delegate: Column {
							id: group

							required property var modelData
							required property int index

							width: groups.width
							spacing: 0


							readonly property bool open: root.state.isGroupOpen(group.modelData.app)
							readonly property int count: group.modelData.items.length

							// The card the keyboard cursor is on, so that the panel can ask
							// the list to scroll it into view without walking the item tree
							// itself.
							function focusedCard() {
								if (root.focusGroup !== group.index)
									return null;
								if (root.focusItem === 0)
									return front;
								return restCards.itemAt(root.focusItem - 1);
							}

							// The card currently showing `notification`, so a
							// deferred dismissal can re-resolve its target after
							// the model has shifted underneath. Null when the
							// group is collapsed and only the front card is drawn.
							function cardShowing(notification) {
								if (front.notification === notification)
									return front;
								for (var r = 0; r < restCards.count; r++) {
									var c = restCards.itemAt(r);
									if (c && c.notification === notification)
										return c;
								}
								return null;
							}

							// swaync draws the group heading only when there is
							// more than one notification in it -- with a single
							// notification the card sits straight under the DND
							// row, which is what the live panel measures.
							Item {
								visible: group.modelData.items.length > 1
								width: parent.width
								implicitHeight: visible ? Math.max(groupLabel.implicitHeight, groupClose.height) + Theme.groupHeaderGap : 0
								height: implicitHeight

								Text {
									id: groupLabel

									anchors.left: parent.left
									anchors.leftMargin: Theme.groupSideMargin
									anchors.verticalCenter: parent.verticalCenter
									text: group.modelData.app
									font.family: Theme.fontFamily
									font.pixelSize: Theme.groupHeaderSize
									font.weight: Theme.groupHeaderWeight
									color: colors.text
								}

								// The chevron sits beside the title rather than at the far end
								// of the row, where the close-all button is: it belongs to the
								// name it opens, not to the row.
								Rectangle {
									id: groupToggle

									anchors.left: groupLabel.right
									anchors.leftMargin: Theme.groupToggleGap
									anchors.verticalCenter: parent.verticalCenter
									width: Theme.groupCloseSize
									height: Theme.groupCloseSize
									radius: Theme.cardRadius
									color: groupToggleArea.containsMouse ? colors.hoverAlt : "transparent"

									SymbolicIcon {
										anchors.centerIn: parent
										width: Theme.groupToggleIconSize
										height: Theme.groupToggleIconSize
										source: Quickshell.iconPath(group.open ? Theme.groupToggleIconOpen : Theme.groupToggleIcon, true)
										color: colors.text
									}

									MouseArea {
										id: groupToggleArea

										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.PointingHandCursor
										onClicked: root.openFocusedGroup(!group.open, group.index)
									}
								}

								Rectangle {
									id: groupClose

									anchors.right: parent.right
									anchors.rightMargin: Theme.groupSideMargin
									anchors.verticalCenter: parent.verticalCenter
									width: Theme.groupCloseSize
									height: Theme.groupCloseSize
									radius: Theme.cardRadius
									color: groupCloseArea.containsMouse ? colors.hoverAlt : "transparent"

									SymbolicIcon {
										anchors.fill: parent
										anchors.margins: 4
										source: Quickshell.iconPath("window-close-symbolic", true)
										color: colors.text
									}

									MouseArea {
										id: groupCloseArea

										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.PointingHandCursor
										onClicked: root.dismissGroupVisually(group, 0)
									}
								}
							}

							// ── the cards ────────────────────────────────────────────────
							// Collapsed (swaync's default, and what its own panel measures)
							// the group is one card tall: the newest notification in full,
							// with the older ones behind it as the edges of a stack that
							// descends *below* it -- newest on top, then the next, which is
							// also the order an expanded group draws its rows in.
							Item {
								id: stack

								width: group.width
								// How many edges of the cards behind are drawn. Never more
								// than the pile tokens allow, and never for a group that is
								// open or has nothing behind it.
								readonly property int edges: (!group.open && group.count > 1)
									? Math.min(group.count - 1, Theme.pileMaxEdges)
									: 0
								implicitHeight: group.open
									? (front.implicitHeight + Theme.centerCardGap + restCardColumn.implicitHeight)
									: (front.implicitHeight + stack.edges * Theme.pileStep)
								height: implicitHeight

								// The edges. Drawn rather than laid out: the cards behind
								// would be the same width as the front one with their upper
								// halves hidden by it, so only the strip below the front
								// card can ever show, and two rounded rectangles say as much
								// as two more cards would.
								Repeater {
									model: stack.edges

								delegate: Rectangle {
									required property int index

									// The nearest edge is the first one, so the ones behind
										// sit a step lower and a step further in.
										readonly property int depth: index + 1
										// Declared in the wrong order for painting -- the Repeater draws
										// index 0 first and index 0 is the edge nearest the front --
										// so the stacking is set explicitly. Deeper edges sink, and
										// each one is then covered by the edge in front of it, which
										// sits a step higher, except for its own step of bottom
										// edge, which is the whole effect.
										z: -depth
										x: Theme.pileInset * depth
										y: depth * Theme.pileStep
										width: stack.width - Theme.pileInset * depth * 2
										height: front.implicitHeight
										radius: Theme.cardRadius
										color: colors.cardBackground
										border.width: Theme.cardBorderWidth
										border.color: colors.border
									}
								}

								// The newest notification, always drawn: collapsed it is the
								// whole group, expanded it is the row under the header.
								NotifCard {
									id: front

									// The newest is at the top of the stack; the older edges
									// step out below it.
									y: 0
									width: stack.width
									notification: group.modelData.items[0]
									notifColors: colors
									state: root.state
									popup: false
									expandOnClick: !group.open && group.count > 1
									keyFocused: root.rowFocused(group.index, 0)
									onExpandRequested: root.openFocusedGroup(true, group.index)
									onKeyFocusedChanged: if (keyFocused) root.ensureVisible(front)
								}

								// The rest of them, only while the group is open.
								Column {
									id: restCardColumn

									visible: group.open
									y: front.implicitHeight + Theme.centerCardGap
									width: stack.width
									spacing: Theme.centerCardGap

									Repeater {
										id: restCards
										model: group.open ? group.modelData.items.slice(1) : []

										delegate: NotifCard {
											id: restCard

											required property var modelData
											required property int index

											width: stack.width
											notification: modelData
											notifColors: colors
											state: root.state
											popup: false
											keyFocused: root.rowFocused(group.index, index + 1)
											onKeyFocusedChanged: if (keyFocused) root.ensureVisible(restCard)
										}
									}
								}
							}
						}
					}
				}
			}

			// The list's empty state, taking the list's whole area while there is
			// nothing to show -- a message bubble over a line of text, both
			// dimmed, and both swapped for a struck-through bell when DND is what
			// keeps the list empty. A ColumnLayout excludes an invisible item
			// entirely, so the cards' Flickable claims the full height again the
			// moment the first notification lands.
			Item {
				id: emptyState

				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.topMargin: Theme.groupMargin + Theme.centerListTopGap
				visible: root.notificationGroups.length === 0

				Column {
					anchors.centerIn: parent
					spacing: Theme.emptyTextGap

					Text {
						anchors.horizontalCenter: parent.horizontalCenter
						text: root.state.dnd ? Theme.emptyDndGlyph : Theme.emptyBubbleGlyph
						font.family: Theme.fontFamily
						font.pixelSize: Theme.emptyIconSize
						color: colors.dimText
					}

					Text {
						anchors.horizontalCenter: parent.horizontalCenter
						text: root.state.dnd ? Theme.emptyDndText : Theme.emptyText
						font.family: Theme.fontFamily
						font.pixelSize: Theme.emptyTextSize
						color: colors.dimText
					}
				}
			}
		}
	}

	// ── the panel's keyboard ─────────────────────────────────────────────────

	// The panel is walked top to bottom rather than by section: one cursor,
	// moved with j/k or the arrow keys, that visits every stop in the order they
	// are drawn -- the button grid, the volume knob, the brightness knob, the
	// media player, the title row, and then the notifications.
	//
	// Within a stop the horizontal keys do that stop's own thing (which volume,
	// which track, which of the title row's two controls), and so do the vertical
	// ones where the stop is itself two-dimensional, as the grid is. Media
	// playback and the brightness knob are
	// only stops while they exist -- there is nothing to drive otherwise -- which
	// is why this is derived rather than a constant.
	readonly property var stops: {
		var out = ["grid", "volume"];
		if (volume.hasBrightness)
			out.push("brightness");
		if (mpris.hasPlayer)
			out.push("mpris");
		// The title row counts as one stop, not two: its switch and its clear-all
		// button are reached with h/l inside the stop, so j/k pass straight
		// through the row on the way down into the notifications.
		out.push("title", "list");
		return out;
	}

	// Which of the title row's two controls has the cursor: 0 is the DND switch,
	// 1 is clear-all -- left to right, the order they are drawn in. Held rather
	// than derived from stopName the way the grid's own index is, which means the
	// row remembers which control you last used, and that entering it from either
	// side does not reset it.
	property int titleControl: 0

	// Held by name rather than by position, so a brightness slider or a player
	// coming and going under the cursor cannot slide the keyboard onto a
	// different stop. "" means nothing has the cursor yet, which is how the panel
	// opens: the first key press is what puts it on the first body button.
	property string stopName: ""

	function stopIs(name) {
		return root.stopName === name;
	}

	function setStop(name) {
		root.stopName = name;

		// The list owns a cursor of its own; every other stop draws its own focus.
		root.focusActive = (name === "list");
		if (root.focusActive) {
			root.clampFocus();
			root.scrollToFocused();
		}
	}

	// One stop down the panel, or up it. The ends are stops rather than a loop,
	// for the same reason the launcher's list clamps: wrapping from the last
	// notification to the first button is disorienting and easy to do by accident.
	function stepStop(delta) {
		var list = root.stops;
		if (list.length === 0)
			return;

		var index = list.indexOf(root.stopName);
		var fromBelow = false;
		if (index < 0) {
			// Nothing has the cursor: it enters from whichever end the key came
			// from.
			index = delta > 0 ? -1 : list.length;
			fromBelow = delta < 0;
		}

		index = Math.max(0, Math.min(list.length - 1, index + delta));
		var name = list[index];

		// Coming down into the list starts at the newest notification; coming up
		// into it starts at the oldest row, which is the one above the bottom of
		// the panel.
		if (name === "list" && !root.stopIs("list")) {
			if (fromBelow)
				root.focusLastRow();
			else {
				root.focusGroup = 0;
				root.focusItem = 0;
			}
		}

		root.setStop(name);
	}

	// ── the keyboard cursor ──────────────────────────────────────────────────

	// Whether the list has the keyboard, i.e. whether its cursor is drawn.
	property bool focusActive: false
	property int focusGroup: 0
	property int focusItem: 0

	function rowFocused(g, i) {
		return root.focusActive && root.focusGroup === g && root.focusItem === i;
	}

	function groupAt(g) {
		var groups = root.notificationGroups;
		return (g >= 0 && g < groups.length) ? groups[g] : null;
	}

	// The last row of a group: everything in an open one, or just the front card
	// of a collapsed one, because the notifications behind it are not drawn and
	// so cannot be navigated to.
	function maxRowInGroup(g) {
		var group = root.groupAt(g);
		if (!group)
			return 0;
		return (root.state.isGroupOpen(group.app) || group.items.length === 1) ? group.items.length - 1 : 0;
	}

	// The list changes under the cursor whenever a notification arrives or goes.
	function clampFocus() {
		var groups = root.notificationGroups;
		if (groups.length === 0) {
			root.focusGroup = 0;
			root.focusItem = 0;
			return;
		}

		if (root.focusGroup < 0)
			root.focusGroup = 0;
		if (root.focusGroup >= groups.length)
			root.focusGroup = groups.length - 1;

		var last = root.maxRowInGroup(root.focusGroup);
		if (root.focusItem < 0)
			root.focusItem = 0;
		if (root.focusItem > last)
			root.focusItem = last;
	}

	// The last row of the whole list, for the one way the cursor can arrive at the
	// list from below.
	function focusLastRow() {
		var groups = root.notificationGroups;
		if (groups.length === 0) {
			root.focusGroup = 0;
			root.focusItem = 0;
			return;
		}

		root.focusGroup = groups.length - 1;
		root.focusItem = root.maxRowInGroup(root.focusGroup);
	}

	// Leaving an expanded group closes it again, in either direction. The stack is
	// something you open to read and close as you walk out of it, rather than
	// leaving it sprawled open for the rest of the panel.
	function collapseOnExit(g) {
		var group = root.groupAt(g);
		if (!group)
			return;
		if (group.items.length > 1 && root.state.isGroupOpen(group.app))
			root.state.setGroupOpen(group.app, false);
	}

	// One row at a time, across group boundaries: the list is drawn as groups but
	// navigated as a single column. Leaving a group for another one closes it, and
	// walking off the top of the list hands the cursor back to the DND switch above
	// it. Off the bottom there is nothing to walk to, so the cursor stops on the
	// last row of the last group and leaves that group open.
	//
	// Returns whether the key found a row to move to. An empty list has none, and
	// reports that rather than swallowing the key: the caller then steps the cursor
	// out to the stop above, which is the only way back up out of a list with no
	// notifications in it -- there is nothing there to open, activate or delete.
	function moveFocus(step) {
		var groups = root.notificationGroups;
		if (groups.length === 0)
			return false;

		root.clampFocus();

		var g = root.focusGroup;
		var i = root.focusItem + step;

		while (g >= 0 && g < groups.length) {
			if (i > root.maxRowInGroup(g)) {
				// Nothing below the last group, so stopping here is the whole
				// move -- and collapsing a group the user is reading because they
				// tried to walk past its end would be losing their place rather
				// than leaving it. With another group after this one there is
				// somewhere to go, and walking out closes it as before.
				if (g === groups.length - 1) {
					root.focusGroup = g;
					root.focusItem = root.maxRowInGroup(g);
					root.scrollToFocused();
					return true;
				}

				root.collapseOnExit(g);
				g += 1;
				i = 0;
				continue;
			}
			if (i < 0) {
				root.collapseOnExit(g);
				g -= 1;
				i = g >= 0 ? root.maxRowInGroup(g) : 0;
				continue;
			}

			root.focusGroup = g;
			root.focusItem = i;
			root.scrollToFocused();
			return true;
		}

		// Ran off an end of the list: the cursor steps out to the stop above, or
		// stops on the last row.
		if (g < 0)
			root.stepStop(-1);
		else
			root.focusLastRow();

		return true;
	}

	function focusedNotification() {
		var group = root.groupAt(root.focusGroup);
		if (!group)
			return null;
		return group.items[root.focusItem] ? group.items[root.focusItem] : null;
	}

	// h / l, and the chevron. `g` is given by the chevron, which knows its own
	// group; the keys use the cursor's.
	function openFocusedGroup(open, g) {
		var group = root.groupAt(g === undefined ? root.focusGroup : g);
		if (!group)
			return;

		root.state.setGroupOpen(group.app, open);

		// Closing hides every row of the group but the front one, so the cursor
		// has to end up on the row that is left.
		if (g === undefined || root.focusGroup === g) {
			if (!open)
				root.focusItem = 0;
			root.clampFocus();
			root.scrollToFocused();
		}
	}

	// Enter. On a collapsed group that means the same thing a click on it does.
	function activateFocused() {
		var group = root.groupAt(root.focusGroup);
		if (!group)
			return;

		if (!root.state.isGroupOpen(group.app) && group.items.length > 1) {
			root.openFocusedGroup(true);
			return;
		}

		var notification = root.focusedNotification();
		if (!notification)
			return;

		var actions = notification.actions ? notification.actions : [];
		for (var i = 0; i < actions.length; i++) {
			if (actions[i].identifier === "default") {
				actions[i].invoke();
				return;
			}
		}
	}

	// Delete / Backspace / c / d: the notification under the cursor, or the
	// newest one when there is nothing to point at.
	function dismissFocused() {
		var group = groupRepeater.itemAt(root.focusGroup);
		if (!group) {
			root.state.closeLatest();
			return;
		}

		// A collapsed stack leaves as one pile -- the same thing a swipe on
		// the front card means. An expanded group loses the row the cursor is
		// on and keeps the rest.
		if (root.focusItem === 0 && !group.open && group.count > 1) {
			root.dismissGroupVisually(group, 0);
			return;
		}

		var notification = root.focusedNotification();
		if (notification) {
			root.flyNotificationLater(notification, 0);
		} else if (root.state.tracked.length > 0) {
			// The cursor is on a row the list no longer shows; whatever is
			// newest takes the animated exit rather than vanishing.
			root.flyNotificationLater(root.state.tracked[0], 0);
		}
	}

	// ── the keys ─────────────────────────────────────────────────────────────

	// One cursor, one meaning per axis. Vertical keys walk the panel: within a
	// stop if the stop is a column of its own (the grid, the notification list),
	// otherwise on to the next stop. Horizontal keys do the current stop's own
	// thing, as they do in the launcher. Returns false for a key no stop has a
	// use for, and the panel then leaves the key alone.
	function handleKey(event) {
		var key = event.key;
		var text = event.text;
		var shifted = (event.modifiers & Qt.ShiftModifier) !== 0;

		var down = (key === Qt.Key_Down || text === "j");
		var up = (key === Qt.Key_Up || text === "k");
		var right = (key === Qt.Key_Right || text === "l");
		var left = (key === Qt.Key_Left || text === "h");
		var activate = (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space);

		if (root.stopIs("grid")) {
			// The buttons are a grid, so h/l step one and j/k step a whole row --
			// until there is no row left to step to, and then the cursor is on
			// its way out to the volume knob below.
			if (right) {
				grid.moveFocus(1);
				return true;
			}
			if (left) {
				grid.moveFocus(-1);
				return true;
			}
			if (down || up) {
				var row = grid.focusedIndex + (down ? Theme.gridColumns : -Theme.gridColumns);
				if (row >= 0 && row < Theme.gridButtons.length)
					grid.setFocus(row);
				else
					root.stepStop(down ? 1 : -1);
				return true;
			}
			if (activate) {
				grid.activate(grid.focusedIndex);
				return true;
			}
		} else if (root.stopIs("volume")) {
			if (right || left) {
				volume.adjustVolume(right ? Theme.sliderStep : -Theme.sliderStep);
				return true;
			}
			// Mute has no slider of its own, so it is this stop's activate key --
			// what the glyph does when clicked -- with `m` as the mnemonic for it.
			if (activate || text === "m") {
				volume.toggleMute();
				return true;
			}
			if (down || up) {
				root.stepStop(down ? 1 : -1);
				return true;
			}
		} else if (root.stopIs("brightness")) {
			if (right || left) {
				volume.adjustBrightness(right ? Theme.sliderStep : -Theme.sliderStep);
				return true;
			}
			if (down || up) {
				root.stepStop(down ? 1 : -1);
				return true;
			}
		} else if (root.stopIs("mpris")) {
			if (right) {
				mpris.nextTrack();
				return true;
			}
			if (left) {
				mpris.previousTrack();
				return true;
			}
			// Both activate keys, as at every other stop: the media box has one
			// action, so Enter and Space both play or pause.
			if (activate) {
				mpris.togglePlay();
				return true;
			}
			if (down || up) {
				root.stepStop(down ? 1 : -1);
				return true;
			}
		} else if (root.stopIs("title")) {
			// The row's two controls are a line, not a column: h/l step between
			// them and clamp at either end, so neither of them is ever a way out
			// of the row. j/k are, which is what makes the row a single stop.
			if (right || left) {
				root.titleControl = right ? 1 : 0;
				return true;
			}
			if (activate) {
				if (root.titleControl === 0)
					root.state.toggleDnd();
				else
					root.dismissAllVisually();
				return true;
			}
			if (down || up) {
				root.stepStop(down ? 1 : -1);
				return true;
			}
		} else if (root.stopIs("list")) {
			if (down || up) {
				// No notifications means no row to walk, so the cursor leaves
				// the list rather than the list keeping the key. Down from here
				// has nowhere to go and clamps, exactly as it does inside a list
				// whose last row the cursor is already on.
				if (!root.moveFocus(down ? 1 : -1))
					root.stepStop(down ? 1 : -1);
				return true;
			}
			// h/l are the tree keys on a group: what the chevron does, and the
			// only way to open one without activating it.
			if (right || left) {
				root.openFocusedGroup(right);
				return true;
			}
			if (activate) {
				root.activateFocused();
				return true;
			}
			// Shift-d clears the list, the same thing the title row's button
			// does; d on its own deletes what the cursor is on. The shifted
			// event's text is "D", so both cases have to match.
			if ((text === "d" || text === "D") && shifted) {
				root.dismissAllVisually();
				return true;
			}
			if (key === Qt.Key_Delete || key === Qt.Key_Backspace || text === "d" || text === "c") {
				root.dismissFocused();
				return true;
			}
		} else if (down || up) {
			// Nothing has the cursor yet: the first vertical key is what puts it
			// on the first stop.
			root.stepStop(down ? 1 : -1);
			return true;
		}

		// Outside the list `d` is still the DND switch. Inside it, `d` is the key
		// that deletes.
		if (text === "d") {
			root.state.toggleDnd();
			return true;
		}

		return false;
	}

	// The rows are a Column inside the Flickable, so a row's place in the view is
	// mapped rather than added up.
	function ensureVisible(item) {
		if (!item || list.height <= 0)
			return;

		var top = item.mapToItem(list.contentItem, 0, 0).y;
		var bottom = top + item.height;
		var margin = Theme.focusScrollMargin;

		if (top < list.contentY + margin)
			list.contentY = Math.max(0, top - margin);
		else if (bottom > list.contentY + list.height - margin)
			list.contentY = Math.min(Math.max(0, list.contentHeight - list.height), bottom - list.height + margin);
	}

	// A row that has only just been created is not laid out yet, hence the turn
	// of the event loop.
	function scrollToFocused() {
		Qt.callLater(root.doScrollToFocused);
	}

	function doScrollToFocused() {
		var group = groupRepeater.itemAt(root.focusGroup);
		if (group)
			root.ensureVisible(group.focusedCard());
	}

	// ── the dismissal sweep ──────────────────────────────────────────────────
	// Keyboard and button dismissals give the card the same exit a swipe does:
	// the card itself flies, fading as it goes. The group's model shifts the
	// instant a notification is dismissed -- the front card is re-filled with
	// the next one, the rest re-index, and the Repeater rebuilds the delegates
	// -- so no card reference can be trusted across a beat.
	//
	// Two things keep the flights alive through that churn. Every deferred
	// step is anchored to the notification object, which the server keeps
	// stable, and re-resolves its card when it fires. And while a sweep is
	// running, the list's model binding is pinned to its previous value, so
	// the Repeater keeps the delegates that are mid-flight instead of
	// rebuilding them from a changed model.
	property bool sweepActive: false

	// The front card of a group's stack, or null. It sits two levels down:
	// group Column -> stack Item -> NotifCard.
	function frontCardOf(group) {
		for (var i = 0; i < group.children.length; i++) {
			var lvl1 = group.children[i];
			if (!lvl1)
				continue;
			for (var j = 0; j < lvl1.children.length; j++) {
				var c = lvl1.children[j];
				if (c && c.notification !== undefined && c.width > 50)
					return c;
			}
		}
		return null;
	}

	// The collapsed pile (front card + stepped edges) of the group named
	// `key`, or null. Resolved fresh at fire time because delegates do not
	// survive a model regeneration.
	function pileForGroup(key) {
		for (var g = 0; g < groupRepeater.count; g++) {
			var grp = groupRepeater.itemAt(g);
			if (!grp || grp.modelData.app !== key)
				continue;
			if (grp.open || grp.count <= 1)
				return null;
			var front = root.frontCardOf(grp);
			if (front)
				return front.parent;
		}
		return null;
	}

	// Pins the list's model for the length of a sweep: taken at sweep start,
	// released at sweep end. The Repeater only rebuilds when the binding's
	// value actually changes, so holding one reference means zero rebuilds.
	property var modelPrevious: null

	function beginSweep(holdMs) {
		if (root.sweepActive)
			return;
		root.sweepActive = true;
		root.modelPrevious = root.notificationGroups;
		root.scheduleLater(holdMs, function() {
			root.sweepActive = false;
			root.modelPrevious = null;
		});
	}

	// The card currently showing `notification`, in any group, or null. Safe
	// to call after model shifts: it asks the delegates that exist now.
	function cardForNotification(notification) {
		for (var g = 0; g < groupRepeater.count; g++) {
			var grp = groupRepeater.itemAt(g);
			if (!grp)
				continue;
			var c = grp.cardShowing(notification);
			if (c)
				return c;
		}
		return null;
	}

	// A collapsed group leaves as one pile -- the newest card plus its stepped
	// edges, exactly as it sits -- while an expanded one leaves one card at a
	// time, front to back. `start` staggers the launches so a cascade of
	// groups reads as one sweep. Takes the delegate only to read its model;
	// nothing captured here outlives the current call.
	function dismissGroupVisually(group, start) {
		var key = group.modelData.app;
		var items = group.modelData.items;
		if (items.length === 0)
			return;

		// The pin has to outlive this group's last flight -- and the pile's
		// guard sweep -- by a comfortable margin. A collapsed stack is one
		// beat (the pile flies as a unit); an expanded group is one per card.
		var flights = (!group.open && items.length > 1) ? 1 : items.length;
		root.beginSweep(start + flights * Theme.dismissCascadeStagger
			+ Theme.dismissFlightPad);

		if (!group.open && items.length > 1) {
			root.flyPileLater(key, items, start);
			return;
		}
		for (var i = 0; i < items.length; i++)
			root.flyNotificationLater(items[i], start + i * Theme.dismissCascadeStagger);
	}

	// Clear-all: every group in display order, one after the next. A collapsed
	// pile occupies one beat (it leaves as one picture); an expanded group
	// takes one per card, so the sweep cascades through them.
	function dismissAllVisually() {
		// One pin for the whole cascade, sized from the beats every group needs
		// plus one flight, so no delegate is ever rebuilt mid-flight.
		var total = 0;
		for (var g = 0; g < groupRepeater.count; g++) {
			var scan = groupRepeater.itemAt(g);
			if (!scan)
				continue;
			var n = scan.modelData.items.length;
			total += (!scan.open && n > 1 ? 1 : n) * Theme.dismissCascadeStagger
				+ Theme.dismissCascadeStagger;
		}
		root.beginSweep(total + Theme.dismissFlightPad);

		var beat = 0;
		for (var g2 = 0; g2 < groupRepeater.count; g2++) {
			var group = groupRepeater.itemAt(g2);
			if (!group)
				continue;
			var items = group.modelData.items;
			var collapsed = !group.open && items.length > 1;
			root.dismissGroupVisually(group, beat);
			beat += (collapsed ? 1 : items.length) * Theme.dismissCascadeStagger + Theme.dismissCascadeStagger;
		}
	}

	// One pile: a picture of the whole stack flies, every notification in the
	// group is dismissed beneath it. The pile is looked up when the beat
	// fires; if it is gone by then (panel closed, group already collapsed to
	// one), each notification falls back to its own card flight.
	function flyPileLater(key, items, delayMs) {
		root.scheduleLater(delayMs, function() {
			var pile = root.pileForGroup(key);
			if (pile && pile.width > 0) {
				// The pile Item owns the edges and the front card, so one
				// transform moves the whole stack and one opacity melts it.
				var fly = Qt.createQmlObject(
					'import QtQuick 2.0\nTranslate { }', pile);
				pile.transform = [fly];

				var slide = Qt.createQmlObject(
					'import QtQuick 2.0\nNumberAnimation { }', pile);
				slide.target = fly;
				slide.property = "x";
				slide.duration = Theme.transition;
				slide.easing.type = Easing.OutCubic;
				slide.from = 0;
				slide.to = pile.width + Theme.dragExitOvershoot;

				var melt = Qt.createQmlObject(
					'import QtQuick 2.0\nNumberAnimation { }', pile);
				melt.target = pile;
				melt.property = "opacity";
				melt.duration = Theme.transition;
				melt.easing.type = Easing.OutCubic;
				melt.to = 0;

				slide.stopped.connect(function() {
					pile.transform = [];
					fly.destroy();
					slide.destroy();
					melt.destroy();
				});
				// The model is pinned for the sweep, so dismissing the whole
				// batch now cannot rebuild the pile out from under its flight.
				// The guard sweep only mops up strays.
				for (var i = 0; i < items.length; i++)
					items[i].dismiss();
				root.scheduleLater(300, function() {
					for (var i = 0; i < items.length; i++)
						items[i].dismiss();
				});
				slide.start();
				melt.start();
				return;
			}
			for (var j = 0; j < items.length; j++)
				root.flyNotificationLater(items[j], j * Theme.dismissCascadeStagger);
		});
	}

	// Flies whichever card is currently showing `notification` on the card's
	// own swipe exit; the flight's onStopped does the dismissal when it
	// lands. Card lookup happens at fire time: the card that showed this
	// notification at schedule time may have been rebuilt away. The guard
	// covers the one way the dismissal can be lost -- a fresh notification
	// rebuilding the delegates mid-flight, which destroys the card and its
	// onStopped with it. Dismissing an already-gone notification is a no-op.
	function flyNotificationLater(notification, delayMs) {
		root.scheduleLater(delayMs, function() {
			var card = root.cardForNotification(notification);
			if (card && card.width > 0) {
				card.dismissing = notification;
				card.flyOut(1);
				root.scheduleLater(600, function() {
					// Guard for a flight killed mid-air by a delegate
					// rebuild. The normal case dismisses from the flight's
					// own end, so by now the wrapper may already be gone --
					// touching a destroyed QObject throws.
					try {
						notification.dismiss();
					} catch (e) {
					}
				});
			} else {
				notification.dismiss();
			}
		});
	}

	// delayMs from now, run f. Always a timer, even for 0: Qt.callLater is
	// queue-based and cannot take a delay, and a synchronous call would let a
	// dismissal mutate the model in the middle of the caller's loop.
	function scheduleLater(delayMs, f) {
		var t = Qt.createQmlObject('import QtQuick 2.0; Timer { }', root);
		t.interval = Math.max(0, delayMs);
		t.repeat = false;
		t.triggered.connect(function() {
			t.destroy();
			f();
		});
		t.start();
	}

	// The IPC close-all (cypher-notify -C, keybinds) asks; the panel answers
	// with the same cascade the panel's own clear button runs.
	Connections {
		target: root.state

		function onClearAllRequested() {
			root.dismissAllVisually();
		}
	}

	// ── grouping ───────────────────────────────────────────────────────────

	// swaync groups the list by application. Stacks are newest-first inside a
	// group and groups are ordered by their newest notification, so a fresh
	// notification always pushes its app to the top.
	readonly property var notificationGroups: {
		var out = [];
		var byApp = ({});
		var all = state.tracked;
		for (var i = 0; i < all.length; i++) {
			var notification = all[i];
			var key = notification.appName ? notification.appName : "Other";
			if (byApp[key] === undefined) {
				byApp[key] = { "app": key, "items": [] };
				out.push(byApp[key]);
			}			byApp[key].items.push(notification);
		}
		return out;
	}
}
