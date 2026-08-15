-- App-specific tweaks (window/layer rules per application)

require("apps.bitwarden")
require("apps.browser")
require("apps.hyprshot")
require("apps.jetbrains")
require("apps.localsend")
require("apps.pip")
require("apps.qemu")
require("apps.retroarch")
require("apps.steam")
require("apps.geforce")
require("apps.system")
require("apps.terminals")
require("apps.walker")
require("apps.webcam-overlay")

-- NOTE: apps/davinci-resolve.conf existed in the hyprlang tree but was not
-- sourced by apps.conf, so apps/davinci-resolve.lua is intentionally not
-- required here either (preserving existing behavior).
