-- Hyprland Lua config entry point
-- Learn how to configure Hyprland: https://wiki.hyprland.org/Configuring/

-- Fallback color variables
require("colors")

-- Pywal16 generated colors (overrides the fallback above when present).
-- Guarded with loadfile so a fresh machine with no pywal cache still works.
local wal_colors = os.getenv("HOME") .. "/.cache/wal/colors-hyprland.lua"
local wal_loader = loadfile(wal_colors)
if wal_loader then
    wal_loader()
end


-- All other hyprland configs
require("default-apps")
require("animations")
require("apps")
require("autostart")
require("bindings.applications")
require("bindings.clipboard")
require("layout")
require("bindings.media")
require("bindings.tiling")
require("bindings.utilities")
require("input")
require("looknfeel")
require("monitors")
require("windows")
require("plugins")


-- XWayland / ecosystem settings (moved here from envs.conf, whose env vars now
-- live in ~/.config/uwsm/env)
hl.config({
    xwayland = {
        force_zero_scaling = true,
    },

    ecosystem = {
        -- Don't show update on first launch
        no_update_news = true,
    },
})


-- Window rules (were at the bottom of hyprland.conf)
hl.window_rule({
    match   = { class = "^(Mouseless)$" },
    no_blur = true,
    center  = true,
})

-- Misc
hl.config({
    misc = {
        focus_on_activate        = true,  -- Enables app auto-focusing
        disable_hyprland_logo    = true,  -- Disables random hyprland logo
        disable_splash_rendering = true,  -- Disables the hyprland splash screen/background
    },
})
