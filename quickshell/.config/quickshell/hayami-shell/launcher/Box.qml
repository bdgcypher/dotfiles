import QtQuick
import Quickshell
import "Metrics.js" as Metrics
import "EmojiData.js" as EmojiData

// The launcher box: the centred rectangle drawn inside its full-screen
// layer surface. Every metric here comes from Metrics.js, which is derived from
// the launcher's layout plus measurements of the rendered box.
//
// The text input owns the query -- the window asks for it through
// queryEdited() and resets it with clear(), which avoids fighting TextInput
// over a bound `text` property.

Item {
	id: box

	property var palette
	property string theme: "default"
	property string placeholder: "  Search..."
	property bool showSearch: true
	property bool showHints: true
	property var results: []
	property int selected: 0
	property int requestedWidth: 0

	// Emoji picker. It shares this box, its search row and its hint bar, and
	// replaces the result list with the grid; `selected` and activated() are the
	// same ones the list uses, so the window drives both the same way.
	property bool emojiMode: false
	property var emojiRows: []
	property var emojiGroups: []
	property int emojiTone: -1
	property int emojiGroupIndex: -1
	property int emojiHovered: -1
	property bool emojiSearching: false

	// The neutral default first, then the five tones. Index 0 means "no tone".
	readonly property var toneSwatches: [""].concat(EmojiData.TONE_MODIFIERS)

	// The row under the pointer. Deliberately separate from `selected`: the
	// keyboard owns the selection, and writing it from a hover re-fires on every
	// list re-layout, which is what used to make ctrl+j/ctrl+k look dead.
	property int hovered: -1

	signal activated(int index)
	signal moved(int delta)
	signal jumped(bool toEnd)
	signal dismissed()
	signal queryEdited(string text)
	signal tabMoved(int delta)
	signal toneCycled()
	signal toneSelected(int tone)
	signal emojiTabRequested(int index)

	readonly property color background: palette && palette.background ? palette.background : "#131317"
	readonly property color foreground: palette && palette.foreground ? palette.foreground : "#c5c4c4"
	readonly property color muted: palette && palette.muted ? palette.muted : "#686766"
	readonly property color accent: palette && palette.accent ? palette.accent : "#CEA56A"

	// style.css uses @color6 for the border and hint rule, @color8 for the faint
	// rules, @color3 for .current.
	readonly property color borderColor: palette && palette.colors && palette.colors.length > 6
		? palette.colors[6] : "#53556A"
	readonly property color dividerColor: muted
	readonly property color selectedColor: palette && palette.colors && palette.colors.length > 3
		? palette.colors[3] : accent

	readonly property bool keybindsTheme: theme === "keybinds"
	readonly property int listMaxHeight: Metrics.listMaxHeightFor(theme)

	// layout.xml spacing: the search row, the content and the hint bar are 10px
	// apart, and #Keybinds adds margin-top: 10 on top of that. GTK gives no
	// spacing around an invisible child, so --nosearch and --nohints drop their
	// gap along with the row itself.
	readonly property int contentGap: showSearch ? Metrics.boxSpacing : 0
	readonly property int hintsGap: showHints ? Metrics.boxSpacing + Metrics.hintsMarginTop : 0

	// One highlight for the keyboard selection and for the row under the pointer,
	// so hovering shows what a click would hit.
	function isHighlighted(index) {
		return index === selected || index === hovered
	}

	// A new result set invalidates the hovered index; without this the row that
	// happens to land on it lights up before the pointer has moved.
	onResultsChanged: hovered = -1

	implicitWidth: requestedWidth > 0 ? requestedWidth : Metrics.defaultBoxWidth
	implicitHeight: Metrics.boxHeightFor(theme)

	function clear() {
		input.text = ""
	}

	function setText(value) {
		input.text = value === undefined || value === null ? "" : String(value)
	}

	function focusInput() {
		input.forceActiveFocus()
	}


	// ── chrome ───────────────────────────────────────────────────────────────
	//
	// A filled rounded rect with the background inset inside it, rather than
	// Rectangle.border whose pen straddles the edge; the bar draws its chrome
	// the same way so both surfaces keep crisp edges.

	Rectangle {
		anchors.fill: parent
		radius: Metrics.boxRadius
		color: box.borderColor
	}

	Rectangle {
		anchors.fill: parent
		anchors.margins: Metrics.boxBorder
		radius: Metrics.boxRadius - Metrics.boxBorder
		color: Qt.rgba(box.background.r, box.background.g, box.background.b, Metrics.boxBgAlpha)
	}

	// Clicks on the box must not reach the window's dismiss handler.
	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.AllButtons
		onClicked: function(mouse) { mouse.accepted = true }
		onWheel: function(wheel) { box.moved(wheel.angleDelta.y > 0 ? -1 : 1) }
	}

	// layout.xml stacks these three in order -- search, then content, then the
	// keybind hints -- so the search input sits at the top of the box with the
	// list beneath it. They are anchored rather than
	// stacked in a Column so that this order is stated once, here.
	Item {
		id: content

		anchors.fill: parent
		anchors.margins: Metrics.boxPadding + Metrics.boxBorder

		// ── list + preview ───────────────────────────────────────────────────

		Item {
			id: contentRow

			anchors.top: searchRow.bottom
			anchors.topMargin: box.contentGap
			anchors.left: parent.left
			width: parent.width
			// The hint bar is pinned to the box bottom, so the content area is
			// whatever is left after the search row, the hints and the gaps the
			// GTK Box spacing puts between them.
			height: parent.height - searchRow.height - hints.height - box.contentGap - box.hintsGap

			// layout.xml: the list is pinned to 260 by .scroll in the default
			// theme, and hexpands in the keybinds theme.
			ListView {
				id: list

				visible: !box.emojiMode
				anchors.left: parent.left
				anchors.top: parent.top
				width: box.keybindsTheme ? parent.width : Metrics.listWidth
				height: Math.min(box.listMaxHeight, contentHeight)
				clip: true
				model: box.results
				currentIndex: box.selected
				highlightFollowsCurrentItem: false
				boundsBehavior: Flickable.StopAtBounds

				onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < count)
					positionViewAtIndex(currentIndex, ListView.Contain)

				delegate: Item {
					id: row

					required property var modelData
					required property int index

					width: list.width
					height: Metrics.rowHeight

					// The focus/hover bar, in the same colour the text takes. It sits
					// left of the icon padding, so it never crowds the label, and runs
					// only as tall as the text rather than the whole row.
					Rectangle {
						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: Metrics.focusBar
						height: Metrics.focusBarHeight
						color: box.selectedColor
						visible: box.isHighlighted(row.index)
					}

					// .item-box { padding: 4px 14px }, .item-image { margin-right: 14px }
					Text {
						id: rowIcon

						x: Metrics.itemPadH
						width: Metrics.itemIconSize + 8
						anchors.verticalCenter: parent.verticalCenter
						text: row.modelData.icon ? row.modelData.icon : ""
						// An image in the icon slot (a clipboard thumbnail, an app icon)
						// replaces the glyph rather than sitting next to it.
						visible: text !== "" && !rowThumb.visible
						font.family: Metrics.fontFamily
						font.pixelSize: Metrics.fontSize
						color: box.isHighlighted(row.index) ? box.selectedColor : box.foreground
						horizontalAlignment: Text.AlignHCenter
						elide: Text.ElideRight
					}

					// The icon slot as an image: a clipboard thumbnail, or an
					// application's themed icon (or an absolute path from the .desktop
					// file's Icon=).
					Image {
						id: rowThumb

						readonly property string imageSrc: !row.modelData.image ? ""
							: (row.modelData.image.charAt(0) === "/"
								? "file://" + row.modelData.image : row.modelData.image)
						// iconPath is already a URL: Quickshell hands back either an
						// absolute path or an image://icon/<name> URL, so it is used as
						// given while a clipboard image needs the file:// scheme.
						readonly property string src: imageSrc !== "" ? imageSrc
							: (row.modelData.iconPath || "")

						x: Metrics.itemPadH
						anchors.verticalCenter: parent.verticalCenter
						width: Metrics.itemIconSize
						height: Metrics.itemIconSize
						// A themed icon that fails to load leaves the row blank instead
						// of showing Qt's broken-image box. Kept in the binding rather
						// than written from onStatusChanged, so a recycled delegate
						// recovers when it is reused for a row whose icon does load.
						visible: src !== "" && status !== Image.Error
						source: src
						sourceSize.width: Metrics.itemIconSize * 2
						sourceSize.height: Metrics.itemIconSize * 2
						fillMode: Image.PreserveAspectFit
						smooth: true
						mipmap: true
					}

					// Title, plus the menu an entry came from when the search reaches
					// the nested menus. Both sit in one centred column, so a row with no
					// path looks exactly as it did before.
					Column {
						id: labelColumn

						x: rowIcon.x + rowIcon.width + Metrics.itemIconMargin
						width: Math.max(0, row.width - x - Metrics.itemPadH)
						anchors.verticalCenter: parent.verticalCenter
						spacing: 0

						Text {
							id: rowLabel

							width: labelColumn.width
							text: row.modelData.text ? row.modelData.text : ""
							font.family: Metrics.fontFamily
							font.pixelSize: Metrics.fontSize
							color: box.isHighlighted(row.index) ? box.selectedColor : box.foreground
							elide: Text.ElideRight
						}

						Text {
							id: rowPath

							width: labelColumn.width
							visible: text !== ""
							text: row.modelData.path ? row.modelData.path : ""
							font.family: Metrics.fontFamily
							font.pixelSize: Metrics.fontSize
							color: box.muted
							elide: Text.ElideRight
						}
					}

					// Hovering only records which row the pointer is over, so it gets the
					// same highlight the keyboard selection uses without moving it;
					// clicking activates the row under the cursor.
					MouseArea {
						anchors.fill: parent
						hoverEnabled: true
						// The row is clickable, so the pointer says so.
						cursorShape: Qt.PointingHandCursor
						onEntered: box.hovered = row.index
						onExited: if (box.hovered === row.index) box.hovered = -1
						onClicked: box.activated(row.index)
					}
				}
			}

			// layout.xml: the preview pane exists only in the default theme,
			// separated from the list by a 1px rule (.preview border-left).
			Item {
				id: preview

				anchors.left: list.right
				anchors.leftMargin: Metrics.previewPadding
				anchors.right: parent.right
				anchors.top: parent.top
				height: list.height

				// The pane shows `preview`, falling back to the entry's subtext (the
				// clipboard's full entry, a file's path, a web search's URL). An
				// entry with neither -- most obviously the app list, whose pane
				// would only restate the name as the entry's long comment -- gets no
				// pane and no divider with it.
				readonly property var selectedItem: box.selected >= 0 && box.selected < box.results.length
					? box.results[box.selected] : null
				readonly property string previewText: !selectedItem ? ""
					: (selectedItem.preview !== undefined ? selectedItem.preview
						: (selectedItem.subtext ? selectedItem.subtext : ""))
				readonly property bool hasImage: selectedItem !== null
					&& selectedItem.image !== undefined && selectedItem.image !== ""
				readonly property string imagePath: hasImage ? selectedItem.image : ""

				// Qualified through preview. rather than bare: the pane's body Text
				// below is no longer named previewText, so an unqualified read here
				// could not silently pick up the wrong object again.
				visible: !box.keybindsTheme && !box.emojiMode
					&& (preview.previewText !== "" || preview.hasImage)

				Rectangle {
					anchors.left: parent.left
					anchors.top: parent.top
					anchors.bottom: parent.bottom
					width: Metrics.previewBorder
					color: box.dividerColor
				}

				// The image itself, when the selected entry is one: the dimensions
				// alone do not tell two screenshots apart. Collapses to nothing for
				// every other kind of entry, so the text below keeps its place.
				Image {
					id: previewImage

					anchors.left: parent.left
					anchors.leftMargin: Metrics.previewPadding + Metrics.previewBorder
					anchors.right: parent.right
					anchors.top: parent.top
				// Nearly the whole pane: the dimensions are on the row, so there is
				// nothing left for the pane to say about an image except show it.
				height: previewImage.visible ? parent.height * 0.9 : 0
					// Guarded: an empty source would be the "file://" root, which Qt
					// tries to open as a directory and warns about.
					source: preview.hasImage ? "file://" + preview.imagePath : ""
					fillMode: Image.PreserveAspectFit
					smooth: true
					visible: preview.hasImage
				}

				Text {
					id: previewBody

					anchors.left: parent.left
					anchors.leftMargin: Metrics.previewPadding + Metrics.previewBorder
					anchors.right: parent.right
					anchors.top: previewImage.bottom
					anchors.topMargin: previewImage.height > 0 ? 8 : 0
					text: preview.previewText
					textFormat: Text.PlainText
					wrapMode: Text.Wrap
					font.family: Metrics.fontFamily
					font.pixelSize: Metrics.fontSize
					color: box.muted
				}
			}

			// layout.xml: the Placeholder label sits in the content container.
			Text {
				anchors.centerIn: parent
				visible: !box.emojiMode && box.results.length === 0
				text: "No Results"
				font.family: Metrics.fontFamily
				font.pixelSize: Metrics.fontSize
				color: box.muted
			}

			// The picker, in the same slot as the list.
			EmojiGrid {
				id: emojiGrid

				anchors.fill: parent
				visible: box.emojiMode
				palette: box.palette
				groups: box.emojiGroups
				rows: box.emojiRows
				selected: box.selected
				hovered: box.emojiHovered
				tone: box.emojiTone
				groupIndex: box.emojiGroupIndex
				searching: box.emojiSearching

				onTabActivated: function(index) { box.emojiTabRequested(index) }
				onActivated: function(flat) { box.activated(flat) }
				onHoverRequested: function(flat) { box.emojiHovered = flat }
			}
		}

		// ── search ───────────────────────────────────────────────────────────

		// style.css: .search-container { padding: 10px; border-bottom: 1px solid @color8 }
		//
		// Kept in the tree when hidden (zero height) so the input can still hold
		// focus for key handling, which is what --nosearch needs.
		Item {
			id: searchRow

			anchors.top: parent.top
			anchors.left: parent.left
			width: parent.width
			height: box.showSearch ? input.height + Metrics.searchPadding * 2 + Metrics.searchBorderBottom : 0
			clip: true

			TextInput {
				id: input

				anchors.left: parent.left
				anchors.right: parent.right
				anchors.top: parent.top
				anchors.topMargin: Metrics.searchPadding

				font.family: Metrics.fontFamily
				font.pixelSize: Metrics.fontSize
				color: box.foreground
				selectByMouse: true
				clip: true
				enabled: box.showSearch

				onTextEdited: box.queryEdited(input.text)

				// .input placeholder { opacity: 0.5 }
				Text {
					anchors.fill: parent
					text: box.placeholder
					font: input.font
					color: box.foreground
					opacity: Metrics.placeholderOpacity
					visible: input.text.length === 0
				}

				// The list moves one item at a time; the grid moves by a cell
				// sideways and by a whole row up and down, so the step depends on
				// which one is showing.
				Keys.onPressed: function(event) {
					var grid = box.emojiMode
					var step = grid ? Metrics.emojiColumns : 1
					var page = grid ? emojiGrid.visibleRows : Metrics.visibleRows(box.theme)

					// The picker's own controls: the list has no equivalent, so
					// they are only handled while the grid is up.
					//
					// Shift+Tab arrives as Key_Backtab rather than Key_Tab with the
					// shift modifier held, which is why it used to do nothing -- and
					// worse, left the key unaccepted for focus traversal to take.
					if (grid && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
						var back = event.key === Qt.Key_Backtab
							|| (event.modifiers & Qt.ShiftModifier)
						box.tabMoved(back ? -1 : 1)
						event.accepted = true
						return
					}
					if (grid && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_T) {
						box.toneCycled()
						event.accepted = true
						return
					}

					switch (event.key) {
					case Qt.Key_Escape:
						box.dismissed()
						event.accepted = true
						break
					case Qt.Key_Return:
					case Qt.Key_Enter:
					case Qt.Key_KP_Enter:
						box.activated(box.selected)
						event.accepted = true
						break
					case Qt.Key_Down:
						box.moved(step)
						event.accepted = true
						break
					case Qt.Key_Up:
						box.moved(-step)
						event.accepted = true
						break
					// Along a row. Unbound in the list.
					case Qt.Key_Right:
						if (grid) {
							box.moved(1)
							event.accepted = true
						}
						break
					case Qt.Key_Left:
						if (grid) {
							box.moved(-1)
							event.accepted = true
						}
						break
					case Qt.Key_PageDown:
						box.moved(step * page)
						event.accepted = true
						break
					case Qt.Key_PageUp:
						box.moved(-step * page)
						event.accepted = true
						break
					case Qt.Key_Home:
						box.jumped(false)
						event.accepted = true
						break
					case Qt.Key_End:
						box.jumped(true)
						event.accepted = true
						break
					default:
						// next = Down/ctrl j, previous = Up/ctrl k.
						// h and l are the vim pair for left and right, and like the
						// arrow keys they only do anything in the grid, where there is a
						// row to move along.
						if (event.modifiers & Qt.ControlModifier) {
							if (event.key === Qt.Key_J) {
								box.moved(step)
								event.accepted = true
							} else if (event.key === Qt.Key_K) {
								box.moved(-step)
								event.accepted = true
							} else if (grid && event.key === Qt.Key_L) {
								box.moved(1)
								event.accepted = true
							} else if (grid && event.key === Qt.Key_H) {
								box.moved(-1)
								event.accepted = true
							}
						}
					}
				}
			}

			Rectangle {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				height: Metrics.searchBorderBottom
				color: box.dividerColor
			}
		}

		// ── hint bar ─────────────────────────────────────────────────────────
		//
		// style.css: .keybind-hints { padding: 10px; margin-top: 10px; border-top: 1px solid @color6 }

		Item {
			id: hints

			anchors.bottom: parent.bottom
			anchors.left: parent.left
			width: parent.width
			height: box.showHints ? hintRow.height + Metrics.hintsPadding * 2 + Metrics.hintsBorderTop : 0
			visible: box.showHints

			Rectangle {
				anchors.top: parent.top
				anchors.left: parent.left
				anchors.right: parent.right
				height: Metrics.hintsBorderTop
				color: box.borderColor
			}

			Row {
				id: hintRow

				anchors.left: parent.left
				anchors.top: parent.top
				anchors.topMargin: Metrics.hintsPadding + Metrics.hintsBorderTop
				spacing: 16

				Repeater {
					model: Metrics.hintsFor(box.emojiMode)

					delegate: Row {
						required property var modelData
						spacing: 6

						Text {
							text: modelData.key
							font.family: Metrics.fontFamily
							font.pixelSize: Metrics.fontSize
							color: box.borderColor
						}

						Text {
							text: modelData.label
							font.family: Metrics.fontFamily
							font.pixelSize: Metrics.fontSize
							color: box.foreground
						}
					}
				}
			}

			// Skin-tone swatches, right-aligned in the hint bar: the neutral default
			// followed by the five tones. Only the picker shows them, because a tone
			// means nothing to the list.
			Row {
				id: swatches

				anchors.right: parent.right
				anchors.verticalCenter: hintRow.verticalCenter
				spacing: Metrics.emojiSwatchSpacing
				visible: box.emojiMode

				Repeater {
					model: box.toneSwatches

					delegate: Item {
						id: swatch

						required property var modelData
						required property int index

						// Index 0 is the neutral default, so its tone is -1.
						readonly property int tone: index - 1
						readonly property bool active: box.emojiTone === tone

						width: Metrics.emojiSwatchSize
						height: Metrics.emojiSwatchSize

						// The tone colour itself, inside the ring and sharing its radius,
						// so the two are one rounded square rather than a square sitting
						// in a rounded outline. Index 0 is the neutral default, filled
						// with the yellow an unmodified emoji is drawn in.
						Rectangle {
							anchors.fill: parent
							radius: Metrics.emojiSwatchRadius
							color: Metrics.emojiToneFill(swatch.tone)
						}

						Rectangle {
							anchors.fill: parent
							radius: Metrics.emojiSwatchRadius
							color: "transparent"
							border.width: 1
							border.color: swatch.active ? box.selectedColor : box.dividerColor
						}

						MouseArea {
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: box.toneSelected(swatch.tone)
						}
					}
				}
			}
		}
	}

	onVisibleChanged: if (visible) input.forceActiveFocus()
	Component.onCompleted: if (visible) input.forceActiveFocus()
}
