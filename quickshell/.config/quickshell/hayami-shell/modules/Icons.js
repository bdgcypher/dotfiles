.pragma library

// Nerd Font glyphs used by the bar.
//
// Written as UTF-16 escapes rather than literal characters so the file stays
// plain ASCII and each glyph is traceable to the codepoint shown in the comment.
// Every one of these was taken from the matching config, so the bar's glyphs
// are traceable to the codepoint named in the comment beside each.

// custom/menu
var menu = "\uDB85\uDDFC" // U+F15FC  nf-md-menu
// hyprland/workspaces format-icons.active
var wsActive = "\uDB85\uDCFB" // U+F14FB  nf-md-circle-medium
// custom/workspace-layout's glyph is not here: that module takes it from
// scripts/workspace-layout.sh itself (U+F056E dwindle, U+EF0D scrolling), so the
// two bars can only ever show the same icon.

// custom/tiling-direction (from scripts/tiling-direction.sh)
var dirHorizontal = "\uDB81\uDCE1" // U+F04E1  nf-md-arrow_split_horizontal
var dirVertical = "\uDB81\uDCE2" // U+F04E2  nf-md-arrow_split_vertical

// group/tray-expander, for the launcher's menu entry rather than the bar itself.
var tray = "\uDB84\uDE94" // U+F1294  nf-md-tray

// The four edges, for the launcher's Bar → Position entries.
var arrowUp = "\uDB80\uDC5D" // U+F005D  nf-md-arrow_up
var arrowDown = "\uDB80\uDC45" // U+F0045  nf-md-arrow_down
var arrowLeft = "\uDB80\uDC4D" // U+F004D  nf-md-arrow_left
var arrowRight = "\uDB80\uDC54" // U+F0054  nf-md-arrow_right

// custom/update
var updates = "\uF2F1" // U+F2F1   nf-fa-rotate
// custom/voxtype
var voxtypeRecord = "\uDB80\uDF6C" // U+F036C  nf-md-microphone
var voxtypeTranscribe = "\uDB81\uDD1F" // U+F051F  nf-md-timer_sand
// custom/screen-recording-indicator
var recordDot = "\uF444" // U+F444   nf-oct-primitive_dot

// group/tray-expander custom/expand-icon. It is the *left* chevron: collapsed
// shows U+F104 as-is, and expanding turns it 180 to point right. (Waybar's
// expander glyph, which this is ported from, is the same left-chevron.)
var trayExpand = "\uF104" // U+F104   nf-fa-angle_left

// tray context menu: the chevron on an entry that opens a submenu. Submenus open
// to the right, so this is the right chevron -- the expander's is not rotated
// here, and reusing it would point the arrow the wrong way.
var traySubmenu = "\uF105" // U+F105   nf-fa-angle_right

// tray context menu: the mark on a checked/selected menu entry (a checkmark
// toggle, and the chosen item in a radio group).
var menuChecked = "\u2713" // U+2713   check mark
var menuSelected = "\u25CF" // U+25CF   black circle

// bluetooth
var btOn = "\uDB80\uDCAF" // U+F00AF  nf-md-bluetooth
var btConnected = "\uDB80\uDCB1" // U+F00B1  nf-md-bluetooth_connect
var btOff = "\uDB80\uDCB2" // U+F00B2  nf-md-bluetooth_off

// network (format-icons signal ladder)
var wifi = [
	"\uDB82\uDD2F", // U+F092F  signal-off
	"\uDB82\uDD1F", // U+F091F  signal 1
	"\uDB82\uDD22", // U+F0922  signal 2
	"\uDB82\uDD25", // U+F0925  signal 3
	"\uDB82\uDD28" // U+F0928  signal 4
]
var ethernet = "\uDB80\uDC02" // U+F0002  nf-md-ethernet
var netOff = "\uDB82\uDD2E" // U+F092E  nf-md-wifi_off

// custom/vpn
var vpn = "\uDB84\uDDA2" // U+F11A2  nf-md-vpn

// custom/agent
//
// The agent module, whose reading comes from scripts/agent-status.sh. The script
// writes the same glyph as an escape of its own, the way vpn-status.sh does, so
// the two can only ever show the same character.
var agent = "\uDB81\uDEA9" // U+F06A9  nf-md-robot

// pulseaudio
var volLow = "\uF027" // U+F027   nf-fa-volume_down
var volHigh = "\uF028" // U+F028   nf-fa-volume_up
var volHeadphone = "\uEE58" // U+EE58   nf-md-headphones
var volHeadset = "\uF025" // U+F025   nf-fa-headphones
var volMuted = "\uEEE8" // U+EEE8   nf-md-volume_off

// memory / cpu
var memory = "\uEFC5" // U+EFC5   nf-md-memory
var cpu = "\uDB80\uDF5B" // U+F035B  nf-md-chip

// custom/notification (the bell's alt values)
//
// The "there are notifications" state uses the plain bell, not bell_badge: the
// bar now draws its own unread dot on the glyph's corner (see BarItem.dot), and
// a badge glyph under a badge would read as two notifications.
var notifActive = "\uDB80\uDC9A" // U+F009A  nf-md-bell
var notifNone = "\uDB80\uDC9C" // U+F009C  nf-md-bell_sleep
var notifDndActive = "\uDB80\uDCA0" // U+F00A0  nf-md-bell_off
var notifDndNone = "\uDB82\uDE93" // U+F0A93  nf-md-bell_off_outline
var notifInhActive = "\uDB80\uDC9B" // U+F009B  nf-md-bell_cancel
var notifInhNone = "\uDB82\uDE91" // U+F0A91  nf-md-bell_cancel_outline

// battery (charging ladder, then discharging ladder)
var batteryCharging = [
	"\uDB82\uDC9C", // U+F089C  battery-charging-10
	"\uDB80\uDC86", // U+F0086  battery-charging-20
	"\uDB80\uDC87", // U+F0087  battery-charging-30
	"\uDB80\uDC88", // U+F0088  battery-charging-40
	"\uDB82\uDC9D", // U+F089D  battery-charging-50
	"\uDB80\uDC89", // U+F0089  battery-charging-60
	"\uDB82\uDC9E", // U+F089E  battery-charging-70
	"\uDB80\uDC8A", // U+F008A  battery-charging-80
	"\uDB80\uDC8B", // U+F008B  battery-charging-90
	"\uDB80\uDC85" // U+F0085  battery-charging (full)
]
var batteryDischarging = [
	"\uDB80\uDC7A", // U+F007A  battery-10
	"\uDB80\uDC7B", // U+F007B  battery-20
	"\uDB80\uDC7C", // U+F007C  battery-30
	"\uDB80\uDC7D", // U+F007D  battery-40
	"\uDB80\uDC7E", // U+F007E  battery-50
	"\uDB80\uDC7F", // U+F007F  battery-60
	"\uDB80\uDC80", // U+F0080  battery-70
	"\uDB80\uDC81", // U+F0081  battery-80
	"\uDB80\uDC82", // U+F0082  battery-90
	"\uDB80\uDC79" // U+F0079  battery (full)
]
var batteryFull = "\uDB80\uDC85" // U+F0085  format-full
