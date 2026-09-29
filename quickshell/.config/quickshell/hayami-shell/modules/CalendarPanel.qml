pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "CalendarModel.js" as Calendar
import "Icons.js" as Icons
import "Theme.js" as Theme

// The clock's calendar, in a flyout off the bar.
//
// It is a *read-out*, not a picker: today is the only marked day, and the one
// thing that moves is which month is on screen -- chevrons, the wheel and the
// arrow keys all step it. There are no events to show and no day to choose, so a
// per-day cursor would be a cursor with nothing to do.
//
// The shape is Omarchy's clock panel (MIT): six fixed rows so the popup is the
// same height in February as in August, ISO week numbers down a gutter, a "W"
// heading that toggles which day the week starts on, the year's own progress
// standing in for a plain rule under the date, and -- once a birth year has been
// given -- a second rail measuring that against a nominal lifetime. The one
// departure is the month stepper *under* the grid rather than over it, where it
// reads as the footer of the block above instead of pushing the grid down.
//
// The panel is a layer surface of its own rather than a popup anchored to the
// clock, for the same reason the tray's is (see TrayExpander): a surface the
// compositor places has no parent for a grab to get refused on, and its size is
// its content's.
Item {
	id: root

	// ── handed down by the clock module ──────────────────────────────────────

	property var pal: null
	property string edge: "top"
	// The screen the bar this clock is on, so the panel lands on the same one.
	property var screenModel: null
	// BarState, for the three preferences the panel keeps -- see BarState's
	// calendar block. A separate object rather than local properties because
	// they are the same kind of thing as the bar's edge: what this machine's
	// shell looks like.
	property var state: null
	// The clock's own corner inside the bar's surface, and how much of the bar it
	// takes up there, so the panel can centre on the module rather than start at
	// its leading edge. See placement below.
	property point anchor: Qt.point(0, 0)
	property size anchorSize: Qt.size(0, 0)

	// Whether the panel is up. The clock toggles it; the panel closes itself on
	// escape, so both write the one property.
	property bool open: false

	// ── the palette ──────────────────────────────────────────────────────────

	readonly property bool vertical: Theme.isVertical(edge)
	readonly property color foreground: pal ? pal.foreground : "#c5c4c4"
	readonly property color background: pal ? pal.background : "#171513"
	// The accent every list in this shell marks focus with, and the colour the
	// rails fill with: @color3 when the palette has it, otherwise the accent.
	readonly property color accent: pal && pal.colors && pal.colors.length > 3
		? pal.colors[3] : (pal && pal.accent ? pal.accent : "#CEA56A")
	readonly property string fontFamily: Theme.fontFamily

	// Dimmed text as a *mix towards the panel's own background* rather than
	// Qt.darker(), which only dims a light-on-dark theme: the bar has been both,
	// and a shade that reads as "quieter" has to move towards whatever is behind
	// it either way.
	function shade(color, mix) {
		var b = root.background
		return Qt.rgba(color.r + (b.r - color.r) * mix,
			color.g + (b.g - color.g) * mix,
			color.b + (b.b - color.b) * mix, 1)
	}

	readonly property color dimText: shade(foreground, 0.35)
	readonly property color dimmerText: shade(foreground, 0.58)
	readonly property color railTrack: shade(foreground, 0.82)
	readonly property color rule: shade(foreground, 0.9)

	// ── today, and the month on screen ───────────────────────────────────────

	property date today: new Date()
	readonly property string todayKey: Calendar.keyForDate(today)

	// Stepping moves these two and nothing else: there is no day cursor to keep
	// in step with them.
	property int viewYear: today.getFullYear()
	property int viewMonth: today.getMonth()
	readonly property date viewDate: new Date(viewYear, viewMonth, 1)
	readonly property bool viewingCurrentMonth: viewYear === today.getFullYear()
		&& viewMonth === today.getMonth()

	// Kept honest across midnight, so the highlight rolls over without the panel
	// being closed and reopened. The month on screen only follows today when it
	// was already on today's month -- stepping back to March and leaving the
	// panel open should not snap it forward at midnight.
	SystemClock {
		id: clock

		precision: SystemClock.Minutes

		onDateChanged: {
			if (Calendar.keyForDate(clock.date) === String(root.todayKey))
				return
			var followToday = root.viewingCurrentMonth
			root.today = clock.date
			if (followToday)
				root.goToToday()
		}
	}

	// ── preferences, and the calendar they make ──────────────────────────────

	readonly property string weekStartSetting: state ? state.calendarWeekStart : ""
	// Unset follows the locale's own first day rather than a hardcoded
	// convention, so a fresh install matches the rest of the desktop.
	readonly property int weekStart: Calendar.normalizedWeekStart(weekStartSetting,
		Qt.locale().firstDayOfWeek)
	readonly property var weekdays: Calendar.weekdayOrder(weekStart)
	readonly property var weeks: Calendar.monthGrid(viewYear, viewMonth, weekStart, todayKey)
	readonly property string nextWeekStartLabel: Qt.locale("en_US")
		.dayName(Calendar.toggledWeekStart(weekStart), Locale.LongFormat)

	readonly property int birthYear: state
		? Calendar.parseBirthYear(state.calendarBirthYear, today.getFullYear()) : 0
	readonly property int age: Calendar.ageFromBirthYear(birthYear, today.getFullYear())
	readonly property int lifeExpectancy: state
		? Calendar.parseLifeExpectancy(state.calendarLifeExpectancy)
		: Calendar.parseLifeExpectancy(0)
	readonly property bool lifeSet: birthYear > 0

	// Pinned to today, not to the month being browsed: stepping through the
	// calendar does not change how much of the year is gone.
	readonly property real yearDone: Calendar.yearProgress(today.getFullYear(),
		today.getMonth(), today.getDate())
	readonly property int yearDonePercent: Calendar.yearProgressPercent(today.getFullYear(),
		today.getMonth(), today.getDate())
	readonly property real lifeDone: Calendar.lifeProgress(age, lifeExpectancy)
	readonly property int lifeDonePercent: Calendar.lifeProgressPercent(age, lifeExpectancy)

	// Which of the two rails is being edited, if either.
	property bool editingLife: false

	// ── acting on it ─────────────────────────────────────────────────────────

	function refresh() {
		today = new Date()
		goToToday()
	}

	function goToToday() {
		viewYear = today.getFullYear()
		viewMonth = today.getMonth()
	}

	function moveMonth(delta) {
		var next = Calendar.stepMonth(viewYear, viewMonth, delta)
		viewYear = next.year
		viewMonth = next.month
	}

	function moveYear(delta) {
		moveMonth(delta * 12)
	}

	function toggleWeekStart() {
		if (!state)
			return
		state.setCalendarWeekStart(Calendar.weekStartSettingName(
			Calendar.toggledWeekStart(weekStart)))
	}

	// Double-tapping the year rail asks for the pair; the inputs are committed
	// together by enter and dropped by escape.
	function startEditingLife() {
		if (!state)
			return
		editingLife = true
		Qt.callLater(function() {
			bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
			expectancyField.text = String(root.lifeExpectancy)
			bornField.selectAll()
			bornField.forceActiveFocus()
		})
	}

	function cancelEditingLife() {
		editingLife = false
		Qt.callLater(function() { keys.forceActiveFocus() })
	}

	function commitLife() {
		if (!state) {
			cancelEditingLife()
			return
		}
		var born = Calendar.parseBirthYear(bornField.text, today.getFullYear())
		var span = Calendar.parseLifeExpectancy(expectancyField.text)
		if (born !== birthYear || span !== lifeExpectancy)
			state.setCalendarLife(born, span)
		cancelEditingLife()
	}

	// Double-tapping the life rail puts it away again. The expectancy stays in
	// the state, so giving a birth year again brings the same span back rather
	// than the default.
	function clearLife() {
		if (!state || !lifeSet)
			return
		state.setCalendarLife(0, lifeExpectancy)
	}

	// Shared by both inputs: tab hops to the other one, enter commits the pair,
	// escape drops the lot.
	function handleLifeKey(event, other) {
		if (event.key === Qt.Key_Escape) {
			cancelEditingLife()
			event.accepted = true
		} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			commitLife()
			event.accepted = true
		} else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
			other.selectAll()
			other.forceActiveFocus()
			event.accepted = true
		}
	}

	// English short day names, like the rest of the shell's type. Where the week
	// starts still follows the locale -- that is a regional convention rather
	// than a translation, and it is overridable above.
	function weekdayLabel(weekday) {
		return String(Qt.locale("en_US").dayName(weekday, Locale.ShortFormat)).toUpperCase()
	}

	// ── where the panel goes ─────────────────────────────────────────────────
	//
	// The tray panel's arithmetic, because a flyout off the bar is the same
	// problem: just past the bar on the axis the bar's thickness occupies, and
	// centred on the module that opened it along the axis the bar runs -- clamped
	// so the whole card stays on screen.

	readonly property real pastBar: Theme.marginTop + Theme.thicknessFor(edge) + Theme.calendarBarGap
	readonly property real screenW: screenModel ? screenModel.width : 0
	readonly property real screenH: screenModel ? screenModel.height : 0

	// Where the bar's strip starts on the screen: the margin it keeps to the edge
	// it is on, and the margin at its ends.
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

	// Read once, as the panel opens, and kept while it is up. The card is an item
	// inside a fixed surface now, so it could follow the clock -- but the clock
	// only drifts for reasons that have nothing to do with this panel (a busy
	// indicator appearing beside it), and a card that jumped a few pixels for
	// those would be the worse trade -- the same call TrayExpander makes for the
	// tray panel.
	property real panelX: 0
	property real panelY: 0

	function takePlace() {
		panelX = followX
		panelY = followY
	}

	// The card: its own size -- the column plus the padding and border the box
	// draws around it -- and where it sits inside the window. The window is the
	// whole screen (see the panel below), so this is what places the visible
	// thing, by the same two rules the window's own margins used to express: just
	// past the bar on the axis the bar's thickness occupies, and the module's own
	// place on the axis the bar runs along.
	readonly property real cardW: column.implicitWidth
		+ (Theme.calendarPad + Theme.calendarBorderWidth) * 2
	readonly property real cardH: column.implicitHeight
		+ (Theme.calendarPad + Theme.calendarBorderWidth) * 2
	readonly property real cardX: vertical
		? (edge === "left" ? pastBar : screenW - pastBar - cardW)
		: panelX
	readonly property real cardY: vertical
		? panelY
		: (edge === "top" ? pastBar : screenH - pastBar - cardH)

	onOpenChanged: {
		if (!open)
			return
		refresh()
		takePlace()
		keys.forceActiveFocus()
	}

	// ── the keyboard ─────────────────────────────────────────────────────────
	//
	// What each key means while the panel is up: it is a whole month of
	// navigable text, and it was opened deliberately, so the arrows belong to it
	// until escape gives the keyboard back with the panel.
	//
	// The handler that feeds these keys is declared inside the panel window
	// below, not here. A key handler only ever sees the keys of the window it is
	// declared in, and this object is declared in the bar's window -- which holds
	// no keyboard at all -- so the window calls the method instead.

	QtObject {
		id: keymap

		function handleKey(event) {
			switch (event.key) {
			case Qt.Key_Left:
			case Qt.Key_H:
				root.moveMonth(-1)
				event.accepted = true
				break
			case Qt.Key_Right:
			case Qt.Key_L:
				root.moveMonth(1)
				event.accepted = true
				break
			case Qt.Key_Up:
			case Qt.Key_K:
				root.moveYear(-1)
				event.accepted = true
				break
			case Qt.Key_Down:
			case Qt.Key_J:
				root.moveYear(1)
				event.accepted = true
				break
			}
			if (event.accepted)
				return
			// The bracket pair Omarchy's calendar uses, kept because a month and
			// a year are two different steps and the arrows alone cannot say
			// which is which without a modifier.
			var text = event.text
			if (text === "[")
				root.moveMonth(-1)
			else if (text === "]")
				root.moveMonth(1)
			else if (text === "{")
				root.moveYear(-1)
			else if (text === "}")
				root.moveYear(1)
			else if (text === "t" || text === "T")
				root.goToToday()
			else if (text === "w" || text === "W")
				root.toggleWeekStart()
			else
				return
			event.accepted = true
		}
	}

	// ── the panel ────────────────────────────────────────────────────────────

	PanelWindow {
		id: panel

		screen: root.screenModel
		visible: root.open

		// Full screen, with the card drawn inside it at cardX/cardY -- the shape the
		// notification centre uses, and for the same reason: a surface bigger than
		// what it draws lets a click *off* the card put the panel away, with no
		// focus event to interpret and no second surface to order against this one.
		// One window, so the card being above the click target is settled by
		// declaration order alone.
		anchors.top: true
		anchors.bottom: true
		anchors.left: true
		anchors.right: true

		exclusiveZone: 0
		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Top
		WlrLayershell.namespace: "quickshell:calendar"
		// Exclusive rather than on-demand: the panel was opened to be read and
		// stepped through, so the arrows belong to it until escape or the clock
		// takes it back.
		WlrLayershell.keyboardFocus: root.open
			? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		// Clicking anywhere the card is not puts the calendar away, the way a menu
		// behaves: the click that dismisses is not passed on to what is under it.
		// Declared before the box so it stays below it, which is what keeps the
		// card's own controls clickable.
		MouseArea {
			anchors.fill: parent
			onClicked: root.open = false
		}

		// Inside this window rather than beside the root object, because a
		// FocusScope handles the keys of the window it is declared in -- and the
		// root object's window is the bar's, which never holds them. What each
		// key means is handleKey() up by the root.
		FocusScope {
			id: keys

			anchors.fill: parent
			focus: root.open

			Keys.onEscapePressed: root.open = false
			Keys.onPressed: (event) => keymap.handleKey(event)
		}

		// The box, drawn the way the bar, the tooltips and the tray panel draw
		// theirs: a rounded rect in the border colour with the background inset
		// inside it, because Qt centres a border pen on the item's outline and
		// clips the outer half.
		Rectangle {
			x: root.cardX
			y: root.cardY
			width: root.cardW
			height: root.cardH
			color: Theme.borderColor
			radius: Theme.calendarRadius

			// The wheel steps the month, the gesture Omarchy's calendar answers to
			// as well. On this rectangle rather than on the window: a pointer
			// handler attaches to an item, and the window is not one -- this is the
			// item that covers the whole surface, so every notch lands here.
			WheelHandler {
				onWheel: function(event) {
					if (event.angleDelta.y === 0)
						return
					root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
				}
			}

			Rectangle {
				anchors.fill: parent
				anchors.margins: Theme.calendarBorderWidth
				color: root.background
				radius: Math.max(Theme.calendarRadius - Theme.calendarBorderWidth, 0)
			}
		}

		Column {
			id: column

			x: root.cardX + Theme.calendarBorderWidth + Theme.calendarPad
			y: root.cardY + Theme.calendarBorderWidth + Theme.calendarPad
			spacing: Theme.calendarGap

			// ── the hero: today, centred ─────────────────────────────────────
			//
			// Once the view has stepped away it is also the way home: clicking
			// the date you are looking for beats hunting for a reset button.
			Item {
				width: gridColumn.width
				height: heroRow.height

				Row {
					id: heroRow

					anchors.horizontalCenter: parent.horizontalCenter
					spacing: 10

					Text {
						id: heroDate

						anchors.verticalCenter: parent.verticalCenter
						text: Qt.formatDate(root.today, "MMMM d")
						color: heroMouse.containsMouse ? root.accent : root.foreground
						font.family: root.fontFamily
						font.pixelSize: Theme.calendarHeroSize
						font.bold: true
					}
				}

				MouseArea {
					id: heroMouse

					x: heroRow.x
					width: heroRow.width
					anchors.top: parent.top
					anchors.bottom: parent.bottom
					// Always live: the date is the way home from a month you have stepped
					// to, and being already home is a click with nothing to do rather
					// than a header that is not a control.
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: root.goToToday()

					Tooltip {
						target: heroMouse
						pal: root.pal
						edge: root.edge
						text: "Back to today"
						hovered: heroMouse.containsMouse
					}
				}
			}

			// ── the year rail ────────────────────────────────────────────────
			//
			// Doubling as the rule under the hero: a plain hairline said nothing,
			// and whole days done over days in the year says the same thing
			// louder. Double-clicking it opens the life pair below.
			Item {
				width: gridColumn.width
				// Tall enough for whichever it is showing: the rail itself, or the
				// pair of inputs the double-tap put in its place. A fixed height
				// would let the inputs overlap the grid below them.
				height: root.editingLife
					? Math.max(lifeEditRow.implicitHeight, Theme.calendarRailHeight)
					: Theme.calendarRailHeight

				// Double-clicked, and the tooltip says so. The band itself is six tall
				// (Theme's calendarRailHeight), so the target is the rail plus the
				// labels' own height around it -- a six-pixel double-click is not a
				// gesture to ask anyone for.
				MouseArea {
					id: yearRailMouse

					anchors.horizontalCenter: parent.horizontalCenter
					anchors.verticalCenter: parent.verticalCenter
					width: parent.width
					height: Math.max(parent.height, 22)
					enabled: !root.editingLife
					hoverEnabled: enabled
					cursorShape: Qt.PointingHandCursor
					onDoubleClicked: root.startEditingLife()

					Tooltip {
						target: yearRailMouse
						pal: root.pal
						edge: root.edge
						text: "Double-click: memento mori"
						hovered: yearRailMouse.containsMouse
					}
				}

				Text {
					id: yearLabel

					visible: !root.editingLife
					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					text: root.today.getFullYear()
					color: root.dimText
					font.family: root.fontFamily
					font.pixelSize: Theme.calendarMonthSize
				}

				Text {
					id: yearPercent

					visible: !root.editingLife
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					text: root.yearDonePercent + "%"
					color: root.foreground
					font.family: root.fontFamily
					font.pixelSize: Theme.calendarMonthSize
				}

				Rectangle {
					id: yearTrack

					visible: !root.editingLife
					anchors.left: yearLabel.right
					anchors.right: yearPercent.left
					anchors.leftMargin: 10
					anchors.rightMargin: 10
					anchors.verticalCenter: parent.verticalCenter
					height: Theme.calendarRailHeight
					radius: height / 2
					color: root.railTrack

					Rectangle {
						width: Math.round(parent.width * root.yearDone)
						height: parent.height
						radius: parent.radius
						color: root.accent

						Behavior on width {
							NumberAnimation {
								duration: 160
								easing.type: Easing.OutCubic
							}
						}
					}
				}

				// The pair the double-tap asks for. A birth year rather than an
				// age, so the rail keeps counting on its own instead of going
				// stale the moment it is entered.
				Row {
					id: lifeEditRow

					visible: root.editingLife
					anchors.centerIn: parent
					spacing: 8

					Text {
						anchors.verticalCenter: parent.verticalCenter
						text: "BORN"
						color: root.dimText
						font.family: root.fontFamily
						font.pixelSize: 10
						font.letterSpacing: 1
					}

					TextInput {
						id: bornField

						width: 56
						anchors.verticalCenter: parent.verticalCenter
						color: root.foreground
						font.family: root.fontFamily
						font.pixelSize: Theme.calendarMonthSize
						inputMethodHints: Qt.ImhDigitsOnly
						selectByMouse: true
						Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
					}

					Text {
						anchors.verticalCenter: parent.verticalCenter
						text: "LIVE TO"
						color: root.dimText
						font.family: root.fontFamily
						font.pixelSize: 10
						font.letterSpacing: 1
					}

					TextInput {
						id: expectancyField

						width: 44
						anchors.verticalCenter: parent.verticalCenter
						color: root.foreground
						font.family: root.fontFamily
						font.pixelSize: Theme.calendarMonthSize
						inputMethodHints: Qt.ImhDigitsOnly
						selectByMouse: true
						Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
					}
				}
			}

			// ── the life rail ────────────────────────────────────────────────
			//
			// Only here once someone has gone looking and given a year: the same
			// rail as the one above it, measured against a nominal lifetime.
			// Double-clicking it puts it away again.
			Item {
				visible: root.lifeSet && !root.editingLife
				width: gridColumn.width
				height: visible ? Theme.calendarRailHeight : 0

				Text {
					id: lifeLabel

					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					text: "LIFE"
					color: root.dimText
					font.family: root.fontFamily
					font.pixelSize: Theme.calendarMonthSize
				}

				Text {
					id: lifePercent

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					text: root.lifeDonePercent + "%"
					color: root.foreground
					font.family: root.fontFamily
					font.pixelSize: Theme.calendarMonthSize
				}

				Rectangle {
					anchors.left: lifeLabel.right
					anchors.right: lifePercent.left
					anchors.leftMargin: 10
					anchors.rightMargin: 10
					anchors.verticalCenter: parent.verticalCenter
					height: Theme.calendarRailHeight
					radius: height / 2
					color: root.railTrack

					Rectangle {
						width: Math.round(parent.width * root.lifeDone)
						height: parent.height
						radius: parent.radius
						color: root.accent

						Behavior on width {
							NumberAnimation {
								duration: 160
								easing.type: Easing.OutCubic
							}
						}
					}
				}

				TapHandler {
					onDoubleTapped: root.clearLife()
				}

				MouseArea {
					id: lifeMouse

					anchors.fill: parent
					hoverEnabled: true
					acceptedButtons: Qt.NoButton

					Tooltip {
						// The whole rail rather than the "LIFE" label: a popup centres
						// on whatever item it is given, and the label sits at the rail's
						// left end, which hung this box off the card's left edge. The
						// rail's own width centres it on the panel, as the year rail's
						// does.
						target: lifeMouse
						pal: root.pal
						edge: root.edge
						// Names the rail and says how to put it away: the rail under
						// the date says how to ask for one, and this is the way back.
						text: "Memento Mori · double-click to clear"
						hovered: lifeMouse.containsMouse
					}
				}
			}

			// ── the month grid ───────────────────────────────────────────────
			//
			// Week numbers down a gutter on the left, then the seven day columns.
			// Always six rows, so the panel is exactly as tall in February as it
			// is in August.
			Column {
				id: gridColumn

				spacing: Theme.calendarCellSpacing

				Row {
					id: headerRow

					spacing: Theme.calendarCellSpacing

					// The week-number heading doubles as the week-start toggle. It
					// is the one control here whose meaning is not self-evident,
					// so it carries a tooltip naming the day the click will switch
					// to.
					Item {
						width: Theme.calendarWeekWidth
						height: Theme.calendarCellHeight

						Text {
							anchors.centerIn: parent
							text: "W"
							color: weekStartMouse.containsMouse ? root.accent : root.dimmerText
							font.family: root.fontFamily
							font.pixelSize: 10
							font.letterSpacing: 1
							font.bold: true
						}

						MouseArea {
							id: weekStartMouse

							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: root.toggleWeekStart()

							Tooltip {
								target: weekStartMouse
								pal: root.pal
								edge: root.edge
								text: "Start weeks on " + root.nextWeekStartLabel
								hovered: weekStartMouse.containsMouse
							}
						}
					}

					Item {
						width: Theme.calendarGutter
						height: Theme.calendarCellHeight
					}

					Repeater {
						model: root.weekdays

						Text {
							required property var modelData

							width: Theme.calendarCellWidth
							height: Theme.calendarCellHeight
							horizontalAlignment: Text.AlignHCenter
							verticalAlignment: Text.AlignVCenter
							text: root.weekdayLabel(modelData)
							color: root.dimText
							font.family: root.fontFamily
							font.pixelSize: 10
							font.letterSpacing: 1
							font.bold: true
						}
					}
				}

				Repeater {
					model: root.weeks

					Row {
						required property var modelData

						spacing: Theme.calendarCellSpacing

						Text {
							width: Theme.calendarWeekWidth
							height: Theme.calendarCellHeight
							horizontalAlignment: Text.AlignHCenter
							verticalAlignment: Text.AlignVCenter
							text: modelData.week
							color: root.dimmerText
							font.family: root.fontFamily
							font.pixelSize: 10
						}

						Item {
							width: Theme.calendarGutter
							height: Theme.calendarCellHeight
						}

						Repeater {
							model: modelData.days

							Rectangle {
								required property var modelData

								width: Theme.calendarCellWidth
								height: Theme.calendarCellHeight
								radius: Theme.calendarCellRadius
								color: "transparent"
								// Today is outlined, not filled: a lit-up block
								// would shout over a grid this quiet.
								border.width: modelData.today ? 1 : 0
								border.color: root.dimText

								Text {
									anchors.centerIn: parent
									text: modelData.day
									color: modelData.inMonth
										? (modelData.weekend ? root.shade(root.foreground, 0.3) : root.foreground)
										: root.dimmerText
									font.family: root.fontFamily
									font.pixelSize: Theme.calendarMonthSize
									font.bold: modelData.today
								}
							}
						}
					}
				}

				// Air before the stepper: the six rows above it are one block, and
				// the stepper is the footer under it rather than a seventh row.
				Item {
					width: gridColumn.width
					height: Theme.calendarGap - Theme.calendarCellSpacing
				}

				// The month stepper, spanning the grid it drives: the chevrons sit
				// on the grid's outer bounds, and the label between them is a fixed
				// width so they hold still from "MAY 2026" to "SEPTEMBER 2026".
				Item {
					width: gridColumn.width
					height: monthLabel.implicitHeight + 6

					Text {
						id: monthLabel

						anchors.horizontalCenter: parent.horizontalCenter
						anchors.verticalCenter: parent.verticalCenter
						width: 130
						horizontalAlignment: Text.AlignHCenter
						text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
						color: root.dimText
						font.family: root.fontFamily
						font.pixelSize: Theme.calendarMonthSize
						font.letterSpacing: 1
					}

					Item {
						id: prevMonth

						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: 22
						height: 22

						Text {
							anchors.centerIn: parent
							text: Icons.trayExpand
							color: prevMouse.containsMouse ? root.accent : root.dimText
							font.family: root.fontFamily
							font.pixelSize: 14
						}

						MouseArea {
							id: prevMouse

							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: root.moveMonth(-1)

							Tooltip {
								target: prevMonth
								pal: root.pal
								edge: root.edge
								text: "Previous month"
								hovered: prevMouse.containsMouse
							}
						}
					}

					Item {
						id: nextMonth

						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						width: 22
						height: 22

						Text {
							anchors.centerIn: parent
							text: Icons.traySubmenu
							color: nextMouse.containsMouse ? root.accent : root.dimText
							font.family: root.fontFamily
							font.pixelSize: 14
						}

						MouseArea {
							id: nextMouse

							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: root.moveMonth(1)

							Tooltip {
								target: nextMonth
								pal: root.pal
								edge: root.edge
								text: "Next month"
								hovered: nextMouse.containsMouse
							}
						}
					}
				}
			}
		}
	}
}
