-- Application bindings

-- Close applications
hl.bind("ALT + W", hl.dsp.window.close(), { description = "Close window" })

hl.bind("ALT + RETURN", hl.dsp.exec_cmd("uwsm-app -- " .. terminal), { description = "Terminal" })

hl.bind(
	"SUPER + SHIFT + F",
	hl.dsp.exec_cmd("uwsm-app -- " .. fileManager),
	{ description = "File manager" }
)

hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("uwsm-app -- " .. browser), { description = "Browser" })

hl.bind(
	"SUPER + SHIFT + ALT + B",
	hl.dsp.exec_cmd("uwsm-app -- " .. browser .. " --private-window"),
	{ description = "Browser (private)" }
)

hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd(terminal .. " -e nvim"), { description = "Editor" })

hl.bind(
	"SUPER + SHIFT + O",
	hl.dsp.exec_cmd("uwsm-app -- obsidian -disable-gpu --enable-wayland-ime"),
	{ description = "Obsidian" }
)

hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("uwsm-app -- slack"), { description = "SLack" })

hl.bind("SUPER + SHIFT + SLASH", hl.dsp.exec_cmd("uwsm-app -- bitwarden"), { description = "Passwords" })

-- Web App bindings

-- If your web app url contains '#', type it as '##' to prevent hyprland treating it as a comment

-- Web App Keybind: Google Messages
hl.bind(
	"SUPER + SHIFT + G",
	hl.dsp.exec_cmd("hypr-firefox-pwa \"https://messages.google.com/web/conversations\" \"Google Messages\""),
	{ description = "Google Messages" }
)


-- Web App Keybind: To Do
hl.bind(
	"SUPER + SHIFT + T",
	hl.dsp.exec_cmd("hypr-firefox-pwa \"https://to-do.live.com/tasks/\" \"To Do\""),
	{ description = "To Do" }
)

-- Web App Keybind: Youtube Music
hl.bind(
	"SUPER + SHIFT + M",
	hl.dsp.exec_cmd("hypr-firefox-pwa \"https://music.youtube.com/\" \"Youtube Music\""),
	{ description = "Youtube Music" }
)
