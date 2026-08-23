-- Menus

hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("walker --width 250"), { description = "Launch apps" })

hl.bind("SUPER + PERIOD", hl.dsp.exec_cmd("walker -m symbols --width 400"), { description = "Emoji picker" })

hl.bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"), { description = "Calculator" })

hl.bind("SUPER + K", hl.dsp.exec_cmd("walker -m menus:system/keybinds --theme keybinds --width 780"), { description = "Keybinds Overview" })

hl.bind("SUPER + CTRL + A", hl.dsp.exec_cmd(terminal .. " --class=floating.About -e sh -c 'fastfetch; exec $SHELL'"), { description = "About" })

-- Aesthetics

hl.bind(
	"SUPER + CTRL + SPACE",
	hl.dsp.exec_cmd("~/.local/bin/set-random-wallpaper"),
	{ description = "Set random background and generate theme colors" }
)

hl.bind(
	"SUPER + SHIFT + W",
	hl.dsp.exec_cmd(terminal .. " --class=floating.Wallpaper -e set-custom-wallpaper"),
	{ description = "Wallpaper picker" }
)

hl.bind(
	"SUPER + W",
	hl.dsp.exec_cmd("~/.local/bin/toggle-theme-mode"),
	{ description = "Toggle applied theme mode (original/rebalanced)" }
)

hl.bind("SUPER + T", hl.dsp.exec_cmd("~/.local/bin/theme-mode toggle"), { description = "Toggle default theme mode" })

hl.bind(
	"SUPER + BACKSPACE",
	hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }),
	{ description = "Toggle window transparency" }
)

-- Notifications

hl.bind("SUPER + CTRL + N", hl.dsp.exec_cmd("swaync-client -t -sw"), { description = "Open notification center" })

hl.bind("SUPER + COMMA", hl.dsp.exec_cmd("swaync-client -a -sw"), { description = "Trigger most recent notification" })

hl.bind(
	"SUPER + ALT + COMMA",
	hl.dsp.exec_cmd("swaync-client --close-latest -sw"),
	{ description = "Dismiss most recent notification" }
)

hl.bind(
	"SUPER + CTRL + COMMA",
	hl.dsp.exec_cmd("swaync-client --close-all -sw"),
	{ description = "Dismiss all notifications" }
)

hl.bind(
	"SUPER + SHIFT + COMMA",
	hl.dsp.exec_cmd("swaync-client -d -sw"),
	{ description = "Toggle do-not-disturb mode" }
)

-- Captures

hl.bind(
	"SUPER + S",
	hl.dsp.exec_cmd(
		[[hyprshot -z -m region --clipboard-only --silent && swayosd-client --custom-message "Screenshot copied to clipboard" --custom-icon "edit-copy"]]
	),
	{ description = "Screenshot to clipboard without editing" }
)

hl.bind(
	"SUPER + CTRL + S",
	hl.dsp.exec_cmd("hyprshot -z -m region --raw --silent | satty --filename -"),
	{ description = "Screenshot with editing" }
)

hl.bind("SUPER + R", hl.dsp.exec_cmd("screen-record"), { description = "Toggle screen recording" })

hl.bind(
	"SUPER + CTRL + C",
	hl.dsp.exec_cmd(
		[[pkill hyprpicker || hyprpicker -a -f hex && swayosd-client --custom-message "Color copied to clipboard" --custom-icon "edit-copy"]]
	),
	{ description = "Color picker" }
)

-- Waybar-less information

hl.bind(
	"SUPER + CTRL + ALT + T",
	hl.dsp.exec_cmd([[notify-send "   $(date +"%A %H:%M  —  %d %B W%V %Y")"]]),
	{ description = "Show time" }
)

-- Control panels

hl.bind(
	"SUPER + CTRL + B",
	hl.dsp.exec_cmd(terminal .. " --class=floating.Bluetui -e bluetui"),
	{ description = "Bluetooth controls" }
)

hl.bind(
	"SUPER + CTRL + W",
	hl.dsp.exec_cmd(terminal .. " --class=floating.Gazelle -e gazelle"),
	{ description = "Wifi controls" }
)

hl.bind(
	"SUPER + CTRL + T",
	hl.dsp.exec_cmd(terminal .. " --class=floating.Btop -e btop"),
	{ description = "Activity monitor" }
)

-- Package Management

hl.bind(
	"SUPER + CTRL + I",
	hl.dsp.exec_cmd(terminal .. " --class=floating.Pacman -e pi"),
	{ description = "Install packages" }
)

hl.bind(
	"SUPER + CTRL + R",
	hl.dsp.exec_cmd(terminal .. " --class=floating.Pacman -e pr"),
	{ description = "Remove Installed packages" }
)

hl.bind(
	"SUPER + CTRL + U",
	hl.dsp.exec_cmd(terminal .. " --class=floating.Pacman -e piu"),
	{ description = "Full system update" }
)

-- Dictation

hl.bind("SUPER + CTRL + X", hl.dsp.exec_cmd("voxtype record start"), { description = "Start dictation" })

hl.bind("SUPER + CTRL + X", hl.dsp.exec_cmd("voxtype record stop"), { release = true, description = "Stop dictation" })

-- Power menu

hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd("walker -m menus:system/power --width 250"), { description = "Power menu" })

-- Lock system

hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), { description = "Lock system" })

-- Turn off laptop screen if docked

hl.bind(
	"switch:on:Lid Switch",
	hl.dsp.exec_cmd(
		[[test "$(hyprctl monitors | grep -c '^Monitor')" -gt 1 && hyprctl eval 'hl.monitor({output="eDP-1",disabled=true})']]
	),
	{ locked = true, description = "Disable internal display on lid close if external monitor attached" }
)

hl.bind(
	"switch:off:Lid Switch",
	hl.dsp.exec_cmd([[hyprctl eval 'hl.monitor({output="eDP-1",disabled=false})']]),
	{ locked = true, description = "Re-enable internal display on lid open" }
)
