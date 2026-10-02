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

-- The coding agent. Tiled rather than floating -- an agent session is something
-- you work in, not a dialog over what you was doing -- and aimed at the home
-- directory, because freebuff has its own project picker and $HOME is the one
-- place that is always a sensible start. `hayami agent new` always opens a new
-- window rather than switching to one that is already up: a second session
-- alongside a running one is a normal thing to want, and each existing session
-- gets its focus from its own row in the panel.
--
-- On the SHIFT because that is the row this desktop launches things from --
-- SUPER+SHIFT for the file manager, the browser, the editor, Obsidian, Slack --
-- and an agent session is another thing you launch. It was SUPER+CTRL+A, which
-- put it in a row of its own for no reason. The bare SUPER+A is the agent
-- *panel* (utilities.lua): reading what the agent is up to is the frequent half
-- and starting a session is the occasional one, so the panel gets the
-- unmodified key and the session gets the modifier its siblings have.
hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd("hayami agent new"), { description = "Coding agent" })

-- The Arch 'bitwarden' package installs /usr/bin/bitwarden-desktop (there is
-- no 'bitwarden' executable); the window still reports class "Bitwarden",
-- which is what hypr/.config/hypr/apps/bitwarden.lua matches on.
hl.bind("SUPER + SHIFT + SLASH", hl.dsp.exec_cmd("uwsm-app -- bitwarden-desktop"), { description = "Passwords" })

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

-- Web App Keybind: Zoom
hl.bind(
	"SUPER + SHIFT + Z",
	hl.dsp.exec_cmd("hypr-firefox-pwa \"https://app.zoom.us/wc/home\" \"Zoom\""),
	{ description = "Zoom" }
)
