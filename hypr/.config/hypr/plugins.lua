-- Hyprland plugins (hyprpm)

hl.config({
	plugin = {
		scrolloverview = {
			gesture_distance = 200,
			scale = 0.6,
			workspace_gap = 0,
			layout = "vertical",
			wallpaper = 0,
			blur = false,
			shadow = {
				enabled = false,
				range = 50,
			},
			input = {
				touchpad_scroll_factor = 5.0,
			},
		},
	},
})

-- 3-finger swipe up/down toggles the overview.
-- The plugin loads via `hyprpm reload` in autostart (after this config runs),
-- so wait until it is available before registering the gestures.
local gesture_timer = hl.timer(function()
	if not hl.plugin.scrolloverview then
		return
	end
	hl.plugin.scrolloverview.gesture({ fingers = 3, direction = "up", action = "overview" })
	hl.plugin.scrolloverview.gesture({ fingers = 3, direction = "down", action = "overview" })
	gesture_timer:set_enabled(false)
end, { timeout = 500, type = "repeat" })

-- Navigate the overview with vim keys and arrow keys.
hl.define_submap("scrolloverview", function()
	hl.bind("h", function()
		hl.plugin.scrolloverview.navigate("left")
	end)
	hl.bind("l", function()
		hl.plugin.scrolloverview.navigate("right")
	end)
	hl.bind("k", function()
		hl.plugin.scrolloverview.navigate("up")
	end)
	hl.bind("j", function()
		hl.plugin.scrolloverview.navigate("down")
	end)

	hl.bind("left", function()
		hl.plugin.scrolloverview.navigate("left")
	end)
	hl.bind("right", function()
		hl.plugin.scrolloverview.navigate("right")
	end)
	hl.bind("up", function()
		hl.plugin.scrolloverview.navigate("up")
	end)
	hl.bind("down", function()
		hl.plugin.scrolloverview.navigate("down")
	end)

	hl.bind("Return", function()
		hl.plugin.scrolloverview.overview("select")
		hl.plugin.scrolloverview.overview("close")
	end)
	hl.bind("escape", function()
		hl.plugin.scrolloverview.overview("off")
	end)

	hl.bind("mouse:272", function()
		hl.plugin.scrolloverview.overview("select")
		hl.plugin.scrolloverview.window("select")
		hl.plugin.scrolloverview.overview("off")
	end, { mouse = true })
	hl.bind("mouse:274", function()
		hl.plugin.scrolloverview.window("close")
	end, { mouse = true })
end)
