-- Input devices

hl.config({
  input = {
    -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt
    kb_layout                   = "us",
    kb_options                  = "compose:caps",

    -- Keyboard repeat
    repeat_rate                 = 40,
    repeat_delay                = 600,

    -- Start with numlock on by default
    numlock_by_default          = true,

    -- Focus doesn't follow cursor movement, only a window
    -- being clicked or focused with keybinds
    follow_mouse                = 0,
    float_switch_override_focus = 0,

    touchpad                    = {
      -- Use natural (inverse) scrolling
      natural_scroll = true,

      -- Control the speed of your scrolling
      scroll_factor = 0.9,
    },
  },
})

-- Scroll nicely in the terminal
hl.window_rule({
  match = { class = "com.mitchellh.ghostty" },
  scroll_touchpad = 0.1,
})

-- Touchpad gestures for changing workspaces
hl.gesture({
  fingers   = 3,
  direction = "horizontal",
  action    = "workspace",
})
