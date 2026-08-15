-- Monitors
-- NOTE: the GDK_SCALE environment variable that lived here moved to
-- ~/.config/uwsm/env (see the uwsm env-var relocation step).

-- Laptop Internal Display (1080p)
hl.monitor({
  output   = "eDP-1",
  mode     = "1920x1080@60",
  position = "auto",
  scale    = 1.1,
  -- Window offset for waybar (was `monitor=,addreserved,40,0,0,0` in hyprland.conf)
})

-- Catch-all fallback for any other resolution (1440p, 4k, ultrawides, etc.)
hl.monitor({
  output   = "",
  mode     = "preferred",
  position = "auto",
  scale    = 1.0,
  -- Window offset for waybar
})

-- Allow fractional scale factors without throwing warnings
hl.config({
  debug = {
    disable_scale_checks = true,
  },
})
