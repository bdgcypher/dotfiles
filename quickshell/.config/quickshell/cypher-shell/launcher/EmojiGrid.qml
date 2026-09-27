import QtQuick
import "Metrics.js" as Metrics
import "EmojiData.js" as EmojiData

// The emoji picker's grid: a category tab strip, then the scrolling grid of
// emoji with a header per section ("Frequently Used", then each category).
//
// It renders inside the launcher box where the result list normally sits, so the
// chrome, the search row and the hint bar are all the box's -- this file is only
// the tabs and the cells. Selection is a flat index handed down by the window;
// `rows` (from EmojiData.buildRows) is what maps that index onto a cell and a row
// to scroll to.
//
// Cells cannot use the list's text-colour trick for the selection, because an
// emoji glyph is rendered in its own colours -- so the highlight is a rounded
// background behind the glyph instead.

Item {
	id: grid

	property var palette
	property var groups: []
	property var rows: []
	property int selected: 0
	property int hovered: -1
	property int tone: -1
	property int groupIndex: -1
	property bool searching: false

	signal tabActivated(int index)
	signal activated(int flatIndex)
	// Named hoverRequested rather than hoveredChanged: the `hovered` property
	// below already generates that signal name, and the two would collide.
	signal hoverRequested(int flatIndex)

	readonly property color foreground: palette && palette.foreground ? palette.foreground : "#c5c4c4"
	readonly property color muted: palette && palette.muted ? palette.muted : "#686766"
	readonly property color selectedColor: palette && palette.colors && palette.colors.length > 3
		? palette.colors[3] : "#CEA56A"
	readonly property color dividerColor: muted

	readonly property int tabCount: groups.length + 1
	readonly property real tabWidth: tabCount > 0 ? width / tabCount : width

	// Flat index -> the row that holds it, so the keyboard can scroll the view.
	function reveal(index) {
		if (index < 0 || rows.length === 0)
			return
		var row = EmojiData.rowForIndex(rows, index)
		if (row >= 0 && row < view.count)
			view.positionViewAtIndex(row, ListView.Contain)
	}

	// Positioning is retried after the current event loop turn as well: switching
	// tab swaps the model, and positionViewAtIndex on a view whose new rows have
	// not been built yet does nothing.
	Timer {
		id: revealRetry

		interval: 0
		repeat: false
		property int target: -1
		// The retry has to pass its own `target`. `grid` has no such property, so
		// `grid.reveal(grid.target)` was reveal(undefined) -- rowForIndex maps that
		// to row 0, so a tick after every move the view was put back at the top,
		// which is what made the selection walk off the bottom without scrolling.
		onTriggered: grid.reveal(revealRetry.target)
	}

	function scheduleReveal(index) {
		reveal(index)
		revealRetry.target = index
		revealRetry.restart()
	}

	// The keyboard drives the selection and the view follows it. Without this the
	// selection would walk off the bottom of the grid with the view never moving,
	// because nothing else scrolls a list whose currentItem is not followed.
	onSelectedChanged: scheduleReveal(selected)
	onRowsChanged: scheduleReveal(selected)

	// The tab under a flat index of the strip: 0 is All, the rest are groups.
	function tabKeyAt(index) {
		return index <= 0 ? EmojiData.ALL_KEY : groups[index - 1].key
	}

	// Rows that fit on screen, for page up/down.
	readonly property int visibleRows: Math.max(1, Math.floor(view.height / Metrics.emojiCellHeight))

	Column {
		anchors.fill: parent
		spacing: Metrics.boxSpacing

		// ── category tabs ────────────────────────────────────────────────────

		Item {
			id: tabs

			width: parent.width
			height: Metrics.emojiTabHeight

			Row {
				anchors.fill: parent

				Repeater {
					model: grid.tabCount

					delegate: Item {
						required property int index

						// -1 is All, otherwise the group this tab stands for.
						readonly property int group: index - 1
						readonly property bool active: grid.groupIndex === group

						width: grid.tabWidth
						height: tabs.height

						// A tab is marked by a rule under it plus the glyph
						// brightening, so the active category is legible without
						// a filled pill.
						Rectangle {
							anchors.horizontalCenter: parent.horizontalCenter
							anchors.bottom: parent.bottom
							width: parent.width * 0.6
							height: Metrics.emojiTabRule
							color: parent.active ? grid.selectedColor : "transparent"
						}

						Text {
							anchors.centerIn: parent
							anchors.verticalCenterOffset: -Metrics.emojiTabRule
							text: EmojiData.tabIcon(grid.tabKeyAt(parent.index))
							font.family: Metrics.emojiFontFamily
							font.pixelSize: Metrics.emojiTabIconSize
							opacity: parent.active ? 1.0 : Metrics.emojiTabInactiveOpacity
						}

						MouseArea {
							anchors.fill: parent
							hoverEnabled: true
							// Tabs are clickable, so the pointer says so.
							cursorShape: Qt.PointingHandCursor
							onClicked: grid.tabActivated(parent.group)
						}
					}
				}
			}

			Rectangle {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				height: Metrics.searchBorderBottom
				color: grid.dividerColor
			}
		}

		// ── the grid ─────────────────────────────────────────────────────────

		ListView {
			id: view

			width: parent.width
			height: parent.height - tabs.height - Metrics.boxSpacing
			clip: true
			model: grid.rows
			boundsBehavior: Flickable.StopAtBounds
			interactive: true
			// The keyboard owns the selection, the pointer only previews, so the
			// view never scrolls itself out from under ctrl+j/k.
			highlightFollowsCurrentItem: false

			delegate: Item {
				id: rowItem

				required property var modelData
				required property int index

				width: view.width
				height: rowItem.modelData.type === "header"
					? Metrics.emojiHeaderHeight
					: Metrics.emojiCellHeight

				// A section header, e.g. "Frequently Used".
				Text {
					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					visible: rowItem.modelData.type === "header"
					text: rowItem.modelData.label
					font.family: Metrics.fontFamily
					font.pixelSize: Metrics.emojiHeaderSize
					font.bold: true
					color: grid.foreground
				}

				Row {
					anchors.fill: parent
					visible: rowItem.modelData.type === "cells"

					Repeater {
						model: rowItem.modelData.entries

						delegate: Item {
							id: cell

							required property var modelData
							required property int index

							// The flat selection index this cell stands for.
							readonly property int flat: rowItem.modelData.index + index * 1
							readonly property bool highlighted: grid.selected === flat
								|| grid.hovered === flat

							width: view.width / Metrics.emojiColumns
							height: Metrics.emojiCellHeight

							// No focus bar here, unlike the list menus: a cell already shows
							// focus with its background highlight, and a bar between two
							// glyphs read as a stray mark.
							Rectangle {
								anchors.centerIn: parent
								width: Metrics.emojiCellSize
								height: Metrics.emojiCellSize
								radius: Metrics.emojiCellRadius
								visible: cell.highlighted
								color: Qt.rgba(grid.selectedColor.r, grid.selectedColor.g,
									grid.selectedColor.b, Metrics.emojiHighlightAlpha)
							}

							Text {
								anchors.centerIn: parent
								text: EmojiData.displayChar(cell.modelData, grid.tone)
								font.family: Metrics.emojiFontFamily
								font.pixelSize: Metrics.emojiSize
							}

							MouseArea {
								anchors.fill: parent
								hoverEnabled: true
								// The cell is clickable, so the pointer says so.
								cursorShape: Qt.PointingHandCursor
								onEntered: grid.hoverRequested(cell.flat)
								onExited: if (grid.hovered === cell.flat) grid.hoverRequested(-1)
								onClicked: grid.activated(cell.flat)
							}
						}
					}
				}
			}

			// An empty grid is normal -- a search that matches nothing, or the
			// history page before anything has been picked -- so this is a quiet
			// line rather than the list's "No Results", and it says which of the
			// two it is.
			Text {
				anchors.centerIn: parent
				width: parent.width * 0.8
				horizontalAlignment: Text.AlignHCenter
				wrapMode: Text.WordWrap
				visible: view.count === 0
				text: grid.searching ? "No emoji" : "Nothing here yet \u2014 emoji you pick show up on this page"
				font.family: Metrics.fontFamily
				font.pixelSize: Metrics.fontSize
				color: grid.muted
			}
		}
	}
}
