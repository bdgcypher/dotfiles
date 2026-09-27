import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../modules"
import "NotifTheme.js" as Theme

// swaync's MPRIS widget: album art, track title and artist, transport controls.
//
// central_control.css:
//   .widget-mpris { border: 1px solid @selected; border-radius: 8px; padding: 8px;
//                   margin: 20px 6px }
//   .widget-mpris-player { border-radius: 8px; padding: 6px 14px; margin: 6px }
//   .widget-mpris button { color: alpha(@text,.5) } :hover { color: @selected }
//   .widget-mpris-title { font-weight: 700; font-size: 1rem }
//   .widget-mpris-subtitle { font-weight: 500; font-size: 0.8rem }
//
// `background-color: @background-sec` on the player box is dropped by GTK (that
// colour is not defined anywhere in the pywal output), so the box draws no
// background -- same as the volume widget above.
//
// There is no player most of the time; the widget is hidden entirely then, as
// swaync hides it.
Item {
	id: root

	required property var notifColors
	// True while the panel's keyboard is on this section: the box takes a
	// background and its accent outline, since there is no cursor to put inside it
	// (the transport is reached with h/l and space, and each button flashes when
	// it fires rather than being pointed at).
	property bool sectionFocused: false
	// The transport call that just went out, by name. A press has no other trace
	// on screen -- next/previous move a title the player owns, and play/pause
	// only swaps the icon -- so the button itself lights for a moment, whether it
	// was reached with `h`/`l`/space or with the mouse.
	property string litAction: ""

	// The first player that is actually playing, else the first one that exists.
	// swaync shows one widget per player; the dotfiles only ever have one.
	readonly property var player: {
		var list = Mpris.players ? Mpris.players.values : [];
		for (var i = 0; i < list.length; i++) {
			if (list[i].isPlaying)
				return list[i];
		}
		return list.length > 0 ? list[0] : null;
	}

	// Whether there is anything to drive. The panel asks this rather than the
	// item's `visible`, which is the *effective* one -- false whenever the panel
	// itself is closed, which would take the media section out of Tab's list.
	readonly property bool hasPlayer: player !== null

	visible: root.hasPlayer

	readonly property string artwork: (player && player.trackArtUrl) ? player.trackArtUrl : ""

	// swaync swaps the symbolic icon with the playback state.
	readonly property string transportIcon: (player && player.isPlaying) ? Theme.mprisPause : Theme.mprisPlay


	implicitHeight: visible ? Theme.mprisMargin * 2 + 2 + Theme.mprisPadding * 2
		+ Theme.mprisPlayerMargin * 2 + Theme.mprisPlayerPaddingV * 2
		+ Math.max(Theme.mprisImageSize, info.implicitHeight) : 0

	Rectangle {
		anchors.fill: parent
		radius: Theme.mprisRadius

		// The keyboard in this section, or the pointer on it: one cue, the same
		// pair of states a notification card answers to.
		readonly property bool pointed: sectionHover.hovered || root.sectionFocused

		color: pointed ? root.notifColors.backgroundAlt : "transparent"
		// At rest the muted outline a notification card wears; pointed at or
		// focused, the accent one a lit card wears (and the box fills behind it).
		border.width: pointed ? Theme.focusBorderWidth : Theme.controlBorderWidth
		border.color: pointed ? root.notifColors.selected : root.notifColors.border

		// The box is not a click target itself -- its buttons are -- so this is a
		// HoverHandler rather than a MouseArea, which would swallow their clicks.
		HoverHandler {
			id: sectionHover
		}

		// ── the player box ───────────────────────────────────────────────────
		Item {
			id: playerBox

			anchors.fill: parent
			anchors.margins: Theme.mprisPadding

			Rectangle {
				anchors.fill: parent
				anchors.margins: Theme.mprisPlayerMargin
				radius: Theme.mprisRadius
				color: "transparent"

				Row {
					id: row

					anchors.centerIn: parent
					spacing: Theme.mprisPlayerPaddingH

					Rectangle {
						id: art

						width: Theme.mprisImageSize
						height: Theme.mprisImageSize
						radius: root.artwork !== "" ? Theme.mprisImageRadius : 0
						color: "transparent"
						clip: true

						Image {
							anchors.fill: parent
							source: root.artwork
							sourceSize.width: Theme.mprisImageSize
							sourceSize.height: Theme.mprisImageSize
							fillMode: Image.PreserveAspectCrop
							asynchronous: true
						}
					}

					Column {
						id: info

						width: Theme.mprisTextWidth
						anchors.verticalCenter: parent.verticalCenter
						spacing: 2

						Text {
							width: parent.width
							text: (root.player && root.player.trackTitle) ? root.player.trackTitle : ""
							textFormat: Text.PlainText
							elide: Text.ElideRight
							font.family: Theme.fontFamily
							font.pixelSize: Theme.fontSize
							font.weight: 700
							color: root.notifColors.text
						}

						Text {
							width: parent.width
							text: {
								if (!root.player)
									return "";
								var artist = root.player.trackArtist ? root.player.trackArtist : root.player.trackArtists;
								var album = root.player.trackAlbum;
								if (artist && album)
									return artist + " — " + album;
								return artist ? artist : (album ? album : "");
							}
							textFormat: Text.PlainText
							elide: Text.ElideRight
							font.family: Theme.fontFamily
							font.pixelSize: Theme.bodySize
							font.weight: 500
							color: root.notifColors.text
							opacity: 0.85
						}

						Row {
							spacing: 4

							Repeater {
								model: [
									{ "icon": Theme.mprisPrevious, "action": "previous" },
									{ "icon": root.transportIcon, "action": "playpause" },
									{ "icon": Theme.mprisNext, "action": "next" }
								]

								delegate: Rectangle {
									id: control

									required property var modelData

									// Lit while hovered, and for a moment after firing.
									readonly property bool lit: controlArea.containsMouse || root.litAction === control.modelData.action

									width: Theme.mprisControlSize
									height: Theme.mprisControlSize
									radius: Theme.mprisRadius
									color: control.lit ? root.notifColors.hoverAlt : "transparent"

									SymbolicIcon {
										anchors.centerIn: parent
										width: 16
										height: 16
										source: Quickshell.iconPath(control.modelData.icon, true)
										color: control.lit ? root.notifColors.selected : root.notifColors.dimText
									}

									MouseArea {
										id: controlArea

										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.PointingHandCursor
										onClicked: root.transport(control.modelData.action)
									}
								}
							}
						}
					}
				}
			}
		}
	}

	Timer {
		id: litTimer

		interval: Theme.transportFlash
		onTriggered: root.litAction = ""
	}

	// The keyboard's transport, so the panel's key handler does not have to know
	// what an MPRIS player is.
	function previousTrack() {
		root.transport("previous");
	}

	function nextTrack() {
		root.transport("next");
	}

	function togglePlay() {
		root.transport("playpause");
	}

	function transport(action) {
		if (!root.player)
			return;
		if (action === "next") {
			if (!root.player.canGoNext)
				return;
			root.player.next();
		} else if (action === "previous") {
			if (!root.player.canGoPrevious)
				return;
			root.player.previous();
		} else {
			if (!root.player.canTogglePlaying)
				return;
			root.player.togglePlaying();
		}

		// Only a call that actually went out lights the button.
		root.litAction = action;
		litTimer.restart();
	}
}
