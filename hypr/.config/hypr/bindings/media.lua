-- OSD media controls

-- hayami-osd takes these flags and draws through the Quickshell
-- shell. It draws on the focused monitor by default, so there is no per-press
-- `hyprctl | jq` here to resolve the monitor -- that substitution ran on every
-- key press and cost ~50ms before hayami-osd even started. Pass --monitor only
-- when the keybind means to aim the OSD somewhere other than focus.
hayami_osd = [[hayami-osd]]

-- Toggle mute (speakers)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("volume-boost mute"), { locked = true })

-- Toggle mute (mic)
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(hayami_osd .. " --input-volume mute-toggle"), { locked = true })

-- Volume raise/lower with custom value
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("volume-boost up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("volume-boost down"), { locked = true, repeating = true })

-- Brightness raise/lower, one binding each ('+'/'-' sign needed). A second Up
-- binding was once present alongside this one; two bindings fire two hayami-osd
-- runs per press, which race on the same backlight.
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(hayami_osd .. " --brightness +5"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(hayami_osd .. " --brightness -5"), { locked = true, repeating = true })

-- Play/Pause current player
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(hayami_osd .. " --playerctl play-pause"))

-- Next song for current player
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(hayami_osd .. " --playerctl next"))
