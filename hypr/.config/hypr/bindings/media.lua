-- SwayOSD media controls

-- Only display the OSD on the currently focused monitor.
-- NOTE: hyprlang `$swayosd-client` variable, made a global here (like default-apps vars).
swayosd_client = [[swayosd-client --monitor "$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')"]]

-- Toggle mute (speakers)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(swayosd_client .. " --output-volume mute-toggle"), { locked = true })

-- Toggle mute (mic)
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(swayosd_client .. " --input-volume mute-toggle"), { locked = true })

-- Volume raise/lower with custom value
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(swayosd_client .. " --output-volume 5"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(swayosd_client .. " --output-volume -5"), { locked = true, repeating = true })

-- Cycle keyboard backlight
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(swayosd_client .. " --brightness raise --device intel_backlight"), { locked = true, repeating = true })

-- Brightness raise/lower with custom value ('+'/'-' sign needed)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(swayosd_client .. " --brightness +5"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(swayosd_client .. " --brightness -10"), { locked = true, repeating = true })

-- Play/Pause current player
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(swayosd_client .. " --playerctl play-pause"))

-- Next song for current player
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(swayosd_client .. " --playerctl next"))
