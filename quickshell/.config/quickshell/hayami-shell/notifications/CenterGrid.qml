import QtQuick
import Quickshell
import "NotifTheme.js" as Theme

// swaync's buttons-grid: the ten launcher buttons at the top of the control
// centre, glyph for glyph and command for command out of its config.json.
//
// central_control.css:
//   .widget-buttons-grid { padding: 6px 2px; margin: 6px; border-radius: 8px;
//                          border: 1px solid @selected; background: transparent }
//   button { margin: 4px 16px; padding: 6px 12px; background: transparent;
//            border-radius: 8px; font-size: x-large }
//   button:hover { background: @hover }
//
// `justify-items: space-between` in GTK means the buttons are spread across the
// row rather than stretched, so each one is a centred box in an equal-width cell
// -- which is also what makes them land on the same columns as swaync's.
Rectangle {
	id: grid

	required property var notifColors
	// True while the panel's keyboard is on this section, and which button it is
	// on. The panel moves the cursor; the ring below draws it.
	property bool sectionFocused: false
	property int focusedIndex: 0

	// Measured on the live panel: the grid's top border sits 41.9 below the
	// card's top border and the box is 87.1 tall, which is
	// 2 (borders) + 12 (padding) + 2 rows.
	readonly property real cellWidth: (width - 2 - Theme.gridPaddingH * 2) / Theme.gridColumns

	readonly property real rowHeight: Theme.gridButtonHeight + Theme.gridButtonMarginV * 2

	implicitHeight: Theme.gridBorderWidth * 2 + Theme.gridPaddingV * 2
		+ Math.ceil(Theme.gridButtons.length / Theme.gridColumns) * rowHeight

	radius: Theme.gridButtonRadius
	color: "transparent"
	// The outline a notification card wears: muted at rest, accent while the
	// panel's keyboard is in here. The width stays put rather than growing with
	// the focus, because the buttons below are inset by it.
	border.width: Theme.gridBorderWidth
	border.color: sectionFocused ? notifColors.selected : notifColors.border

	// The tallest glyph in the set, for the vertical centring of a button whose
	// height is the measured one above.
	TextMetrics {
		id: buttonBox

		font.family: Theme.fontFamily
		font.pixelSize: Theme.gridFontSize
		text: {
			var tallest = "";
			for (var i = 0; i < Theme.gridButtons.length; i++) {
				if (Theme.gridButtons[i].glyph.length > tallest.length)
					tallest = Theme.gridButtons[i].glyph;
			}
			return tallest;
		}
	}

	Grid {
		id: flow

		x: 1 + Theme.gridPaddingH
		y: 1 + Theme.gridPaddingV
		width: parent.width - 2 - Theme.gridPaddingH * 2
		columns: Theme.gridColumns

		Repeater {
			model: Theme.gridButtons

			delegate: Item {
				id: cell

				required property var modelData
				required property int index

				// The keyboard's cursor, which hovers in the same colour as the
				// mouse does but with a ring, so the two are told apart.
				readonly property bool focused: grid.sectionFocused && grid.focusedIndex === cell.index

				width: grid.cellWidth
				height: grid.rowHeight

				Rectangle {
					id: button

					anchors.centerIn: parent
					width: Math.max(glyph.implicitWidth + Theme.gridButtonPaddingH * 2,
						Theme.gridButtonHeight)
					height: Theme.gridButtonHeight
					radius: Theme.gridButtonRadius
					color: (cell.focused || area.containsMouse) ? grid.notifColors.hoverAlt : "transparent"
					// Flat at rest; hovered or keyboard-focused a button wears the
					// accent outline the notification cards use for the same states,
					// at the same weight -- pointed at and aimed at are one cue here,
					// as they are on a card. A border paints inside the item, so
					// appearing never shifts the glyph or the neighbours.
					border.width: (cell.focused || area.containsMouse) ? Theme.focusBorderWidth : 0
					border.color: grid.notifColors.selected

					Text {
						id: glyph

						anchors.centerIn: parent
						text: cell.modelData.glyph
						font.family: Theme.fontFamily
						font.pixelSize: Theme.gridFontSize
						color: grid.notifColors.text
					}

					MouseArea {
						id: area

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: grid.activate(cell.index)
					}
				}
			}
		}
	}

	// ── the keyboard's cursor ────────────────────────────────────────────────

	// `step` is one button for h/l, and the row's worth of buttons for j/k, where
	// the panel has already established that there is a row to step to. Movement
	// wraps, so no horizontal key is ever a dead end in a 5x2 grid.
	function moveFocus(step) {
		grid.setFocus(grid.focusedIndex + step);
	}

	function setFocus(index) {
		var count = Theme.gridButtons.length;
		if (count === 0)
			return;
		grid.focusedIndex = ((index % count) + count) % count;
	}

	function activate(index) {
		var buttons = Theme.gridButtons;
		if (index >= 0 && index < buttons.length)
			Quickshell.execDetached(buttons[index].command);
	}
}
