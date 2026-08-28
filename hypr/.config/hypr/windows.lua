-- Window rules (see https://wiki.hyprland.org/Configuring/Basics/Window-Rules/)

-- Suppress maximize events (Hyprland 0.53+ syntax)
hl.window_rule({
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- Tag all windows for default opacity (apps can override with the -default-opacity tag)
hl.window_rule({
  match = { class = ".*" },
  tag = "+default-opacity",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  no_focus = true,
})

-- Apply default opacity after apps have had a chance to opt out
hl.window_rule({
  match = { tag = "default-opacity" },
  opacity = "0.97 0.9",
})

-- Other App Specific Window Rules

-- Bluetui (floating)
hl.window_rule({
  match = { initial_class = "floating.Bluetui" },
  float = true,
  center = true,
  size = "800 600",
})

-- Btop (floating)
hl.window_rule({
  match = { initial_class = "floating.Btop" },
  float = true,
  center = true,
  size = "1000 800",
})

-- Gazelle-tui (floating)
hl.window_rule({
  match = { initial_class = "floating.Gazelle" },
  float = true,
  center = true,
  size = "800 800",
})

-- File picker (floating, termfilechooser via yazi)
hl.window_rule({
  match = { initial_class = "floating.FilePicker" },
  float = true,
  center = true,
  size = "1200 800",
})

-- Wallpaper picker (floating)
hl.window_rule({
  match = { initial_class = "floating.Wallpaper" },
  float = true,
  center = true,
  size = "1200 800",
})

-- About / Fastfetch (floating)
hl.window_rule({
  match = { initial_class = "floating.About" },
  float = true,
  center = true,
  size = "900 600",
})

-- Global Protect VPN (floating)
hl.window_rule({
  match = { initial_class = "floating.GlobalProtect" },
  float = true,
  center = true,
  size = "400 100",
})

-- Steam Games
hl.window_rule({
  match = { initial_class = "^(steam_app_.*)$" },
  float = true,
  center = true,
  size = "1920 1080",
})

-- Wiremix (floating)
hl.window_rule({
  match = { initial_class = "floating.Wiremix" },
  float = true,
  center = true,
  size = "800 600",
})

-- Prevent Obsidian from stealing focus on reload
hl.window_rule({
  name = "Obsidian",
  match = { class = "^(obsidian)$" },
  focus_on_activate = false,
})

-- Calendar / Aion (floating)
hl.window_rule({
  match = { initial_class = "floating.Calendar" },
  float = true,
  center = true,
  size = "1000 700",
})

-- Package Management TUI's (floating)
hl.window_rule({
  match = { initial_class = "floating.Pacman" },
  float = true,
  center = true,
  size = "800 900",
})

-- Web app installer / remover (floating)
hl.window_rule({
  match = { initial_class = "floating.WebAppInstall" },
  float = true,
  center = true,
  size = "900 650",
})

-- Volume Boost toggle (floating)
hl.window_rule({
  match = { initial_class = "floating.VolumeBoost" },
  float = true,
  center = true,
  size = "400 300",
})

-- Screensaver (TTE)
hl.window_rule({
  match = { class = "org.hypr.screensaver" },
  fullscreen = true,
  float = true,
  stay_focused = true,
  animation = "none",
})

-- Web App: Google Messages
hl.window_rule({
  match = { class = "firefox", title = ".*Google Messages.*" },
  tile = true,
})

-- Web App: To Do
hl.window_rule({
  match = { class = "firefox", title = ".*To Do.*" },
  tile = true,
})

-- Web App: Youtube Music
hl.window_rule({
  match = { class = "firefox", title = ".*Youtube Music.*" },
  tile = true,
})

-- Web App: SSamsung Food
hl.window_rule({
  match = { class = "firefox", title = ".*SSamsung Food.*" },
  tile = true,
})

-- Web App: Samsung Food
hl.window_rule({
  match = { class = "firefox", title = ".*Samsung Food.*" },
  tile = true,
})
