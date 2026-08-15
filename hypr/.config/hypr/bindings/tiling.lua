-- Control tiling

hl.bind("ALT + SLASH", hl.dsp.layout("togglesplit"), { description = "$d Toggle split" }) -- dwindle

hl.bind("ALT + SHIFT + SLASH", hl.dsp.layout("swapsplit"), { description = "$d Swap split" }) -- dwindle

hl.bind("ALT + V", hl.dsp.layout("preselect r"), { description = "$d Spawn next window right" }) -- dwindle

hl.bind("ALT + SHIFT + V", hl.dsp.layout("preselect d"), { description = "$d Spawn next window below" }) -- dwindle

hl.bind("ALT + SUPER + P", hl.dsp.window.pseudo(), { description = "Pseudo window" }) -- dwindle

hl.bind("ALT + T", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle window floating/tiling" })

hl.bind("ALT + T", hl.dsp.window.center(), { description = "Center floating window" })

hl.bind("ALT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Full screen" })

hl.bind("ALT + CTRL + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 2 }), { description = "Tiled full screen" })

hl.bind("ALT + SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "Full width" })

hl.bind("ALT + CTRL + L", hl.dsp.exec_cmd("hypr-toggle-layout"), { description = "Toggle workspace layout (dwindle/scrolling)" })




-- Hayami friendly keybinds using arrow keys


-- Move focus with ALT + up,down,left,right

hl.bind("ALT + left", hl.dsp.focus({ direction = "l" }), { description = "Move window focus left" })
hl.bind("ALT + right", hl.dsp.focus({ direction = "r" }), { description = "Move window focus right" })
hl.bind("ALT + up", hl.dsp.focus({ direction = "u" }), { description = "Move window focus up" })
hl.bind("ALT + down", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })


-- Swap active window with the one next to it with ALT + SHIFT + arrows

hl.bind("ALT + SHIFT + left", hl.dsp.window.swap({ direction = "l" }), { description = "Swap window to the left" })
hl.bind("ALT + SHIFT + right", hl.dsp.window.swap({ direction = "r" }), { description = "Swap window to the right" })
hl.bind("ALT + SHIFT + up", hl.dsp.window.swap({ direction = "u" }), { description = "Swap window up" })
hl.bind("ALT + SHIFT + down", hl.dsp.window.swap({ direction = "d" }), { description = "Swap window down" })


-- Resize active window with arrow keys

hl.bind("ALT + CTRL + left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true, description = "Shrink window left" })
hl.bind("ALT + CTRL + up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true, description = "Shrink window up" })
hl.bind("ALT + CTRL + down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true, description = "Expand window down" })
hl.bind("ALT + CTRL + right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true, description = "Expand window right" })


-- Move floating window with arrow keys (30px increments)

hl.bind("ALT + SHIFT + left", hl.dsp.window.move({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind("ALT + SHIFT + right", hl.dsp.window.move({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind("ALT + SHIFT + up", hl.dsp.window.move({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind("ALT + SHIFT + down", hl.dsp.window.move({ x = 0, y = 30, relative = true }), { repeating = true })




-- QWERTY specific keybindings


-- Move focus with ALT + HJKL

hl.bind("ALT + h", hl.dsp.focus({ direction = "l" }), { description = "Move window focus left" })
hl.bind("ALT + l", hl.dsp.focus({ direction = "r" }), { description = "Move window focus right" })
hl.bind("ALT + k", hl.dsp.focus({ direction = "u" }), { description = "Move window focus up" })
hl.bind("ALT + j", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })


-- Swap active window with the one next to it with ALT + SHIFT + HJKL

hl.bind("ALT + SHIFT + h", hl.dsp.window.swap({ direction = "l" }), { description = "Swap window to the left" })
hl.bind("ALT + SHIFT + l", hl.dsp.window.swap({ direction = "r" }), { description = "Swap window to the right" })
hl.bind("ALT + SHIFT + k", hl.dsp.window.swap({ direction = "u" }), { description = "Swap window up" })
hl.bind("ALT + SHIFT + j", hl.dsp.window.swap({ direction = "d" }), { description = "Swap window down" })


-- Resize active window with UIOP

hl.bind("ALT + u", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true, description = "Shrink window left" })
hl.bind("ALT + i", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true, description = "Shrink window up" })
hl.bind("ALT + o", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true, description = "Expand window down" })
hl.bind("ALT + p", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true, description = "Expand window right" })


-- Move floating window with HJKL (30px increments)

hl.bind("ALT + SHIFT + h", hl.dsp.window.move({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind("ALT + SHIFT + l", hl.dsp.window.move({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind("ALT + SHIFT + k", hl.dsp.window.move({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind("ALT + SHIFT + j", hl.dsp.window.move({ x = 0, y = 30, relative = true }), { repeating = true })




-- Switch workspaces with ALT + [1-9; 0]

hl.bind("ALT + code:10", hl.dsp.focus({ workspace = 1 }), { description = "Switch to workspace 1" })
hl.bind("ALT + code:11", hl.dsp.focus({ workspace = 2 }), { description = "Switch to workspace 2" })
hl.bind("ALT + code:12", hl.dsp.focus({ workspace = 3 }), { description = "Switch to workspace 3" })
hl.bind("ALT + code:13", hl.dsp.focus({ workspace = 4 }), { description = "Switch to workspace 4" })
hl.bind("ALT + code:14", hl.dsp.focus({ workspace = 5 }), { description = "Switch to workspace 5" })
hl.bind("ALT + code:15", hl.dsp.focus({ workspace = 6 }), { description = "Switch to workspace 6" })
hl.bind("ALT + code:16", hl.dsp.focus({ workspace = 7 }), { description = "Switch to workspace 7" })
hl.bind("ALT + code:17", hl.dsp.focus({ workspace = 8 }), { description = "Switch to workspace 8" })
hl.bind("ALT + code:18", hl.dsp.focus({ workspace = 9 }), { description = "Switch to workspace 9" })
hl.bind("ALT + code:19", hl.dsp.focus({ workspace = 10 }), { description = "Switch to workspace 10" })


-- Move active window to a workspace with ALT + SHIFT + [1-9; 0]

hl.bind("ALT + SHIFT + code:10", hl.dsp.window.move({ workspace = 1 }), { description = "Move window to workspace 1" })
hl.bind("ALT + SHIFT + code:11", hl.dsp.window.move({ workspace = 2 }), { description = "Move window to workspace 2" })
hl.bind("ALT + SHIFT + code:12", hl.dsp.window.move({ workspace = 3 }), { description = "Move window to workspace 3" })
hl.bind("ALT + SHIFT + code:13", hl.dsp.window.move({ workspace = 4 }), { description = "Move window to workspace 4" })
hl.bind("ALT + SHIFT + code:14", hl.dsp.window.move({ workspace = 5 }), { description = "Move window to workspace 5" })
hl.bind("ALT + SHIFT + code:15", hl.dsp.window.move({ workspace = 6 }), { description = "Move window to workspace 6" })
hl.bind("ALT + SHIFT + code:16", hl.dsp.window.move({ workspace = 7 }), { description = "Move window to workspace 7" })
hl.bind("ALT + SHIFT + code:17", hl.dsp.window.move({ workspace = 8 }), { description = "Move window to workspace 8" })
hl.bind("ALT + SHIFT + code:18", hl.dsp.window.move({ workspace = 9 }), { description = "Move window to workspace 9" })
hl.bind("ALT + SHIFT + code:19", hl.dsp.window.move({ workspace = 10 }), { description = "Move window to workspace 10" })


-- Move active window silently to a workspace with ALT + SHIFT + SUPER + [1-9; 0]

hl.bind("ALT + SHIFT + SUPER + code:10", hl.dsp.window.move({ workspace = 1, follow = false }), { description = "Move window silently to workspace 1" })
hl.bind("ALT + SHIFT + SUPER + code:11", hl.dsp.window.move({ workspace = 2, follow = false }), { description = "Move window silently to workspace 2" })
hl.bind("ALT + SHIFT + SUPER + code:12", hl.dsp.window.move({ workspace = 3, follow = false }), { description = "Move window silently to workspace 3" })
hl.bind("ALT + SHIFT + SUPER + code:13", hl.dsp.window.move({ workspace = 4, follow = false }), { description = "Move window silently to workspace 4" })
hl.bind("ALT + SHIFT + SUPER + code:14", hl.dsp.window.move({ workspace = 5, follow = false }), { description = "Move window silently to workspace 5" })
hl.bind("ALT + SHIFT + SUPER + code:15", hl.dsp.window.move({ workspace = 6, follow = false }), { description = "Move window silently to workspace 6" })
hl.bind("ALT + SHIFT + SUPER + code:16", hl.dsp.window.move({ workspace = 7, follow = false }), { description = "Move window silently to workspace 7" })
hl.bind("ALT + SHIFT + SUPER + code:17", hl.dsp.window.move({ workspace = 8, follow = false }), { description = "Move window silently to workspace 8" })
hl.bind("ALT + SHIFT + SUPER + code:18", hl.dsp.window.move({ workspace = 9, follow = false }), { description = "Move window silently to workspace 9" })
hl.bind("ALT + SHIFT + SUPER + code:19", hl.dsp.window.move({ workspace = 10, follow = false }), { description = "Move window silently to workspace 10" })


-- Minimize windows

hl.bind("ALT + M", hl.dsp.window.move({ workspace = "special:minimized", follow = false }), { description = "Minimize window" })
hl.bind("ALT + SHIFT + M", hl.dsp.workspace.toggle_special("minimized"), { description = "View minimized windows" })
hl.bind("ALT + SHIFT + M", hl.dsp.submap("minimized"))

hl.define_submap("minimized", function()
    hl.bind("backspace", hl.dsp.window.close())

    -- QWERTY specific
    hl.bind("h", hl.dsp.focus({ direction = "l" }), { description = "Move window focus left" })
    hl.bind("l", hl.dsp.focus({ direction = "r" }), { description = "Move window focus right" })
    hl.bind("k", hl.dsp.focus({ direction = "u" }), { description = "Move window focus up" })
    hl.bind("j", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })
    -- End QWERTY

    -- Hayami friendly (using up,down,left,right)
    hl.bind("left", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })
    hl.bind("right", hl.dsp.focus({ direction = "r" }), { description = "Move window focus right" })
    hl.bind("down", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })
    hl.bind("up", hl.dsp.focus({ direction = "u" }), { description = "Move window focus up" })
    -- End Hayami

    hl.bind("Return", hl.dsp.window.move({ workspace = "+0" }))
    hl.bind("Return", hl.dsp.submap("reset"))

    hl.bind("mouse:272", hl.dsp.window.move({ workspace = "+0" }))
    hl.bind("mouse:272", hl.dsp.submap("reset"))

    hl.bind("escape", hl.dsp.workspace.toggle_special("minimized"))
    hl.bind("escape", hl.dsp.submap("reset"))
end)


-- TAB between workspaces

hl.bind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })
hl.bind("SUPER + CTRL + TAB", hl.dsp.focus({ workspace = "previous" }), { description = "Former workspace" })


-- Move workspaces to other monitors

hl.bind("ALT + SHIFT + SUPER + h", hl.dsp.workspace.move({ monitor = "l" }), { description = "Move workspace to left monitor" })
hl.bind("ALT + SHIFT + SUPER + l", hl.dsp.workspace.move({ monitor = "r" }), { description = "Move workspace to right monitor" })


-- Cycle through applications on active workspace

hl.bind("ALT + TAB", hl.dsp.window.cycle_next({ next = true }), { description = "Cycle to next window" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }), { description = "Cycle to prev window" })
hl.bind("ALT + TAB", hl.dsp.window.bring_to_top(), { description = "Reveal active window on top" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.bring_to_top(), { description = "Reveal active window on top" })

-- Scroll through existing workspaces with ALT + scroll

hl.bind("ALT + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Scroll active workspace forward" })
hl.bind("ALT + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { description = "Scroll active workspace backward" })


-- Move/resize windows with ALT + LMB/RMB and dragging

hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window" })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })


-- Toggle groups

hl.bind("ALT + G", hl.dsp.group.toggle(), { description = "Toggle window grouping" })
hl.bind("ALT + SUPER + G", hl.dsp.window.move({ out_of_group = true }), { description = "Move active window out of group" })


-- Join groups

hl.bind("ALT + SUPER + h", hl.dsp.window.move({ into_group = "l" }), { description = "Move window to group on left" })
hl.bind("ALT + SUPER + l", hl.dsp.window.move({ into_group = "r" }), { description = "Move window to group on right" })
hl.bind("ALT + SUPER + k", hl.dsp.window.move({ into_group = "u" }), { description = "Move window to group on top" })
hl.bind("ALT + SUPER + j", hl.dsp.window.move({ into_group = "d" }), { description = "Move window to group on bottom" })


-- Navigate a single set of grouped windows

hl.bind("ALT + SUPER + TAB", hl.dsp.group.next(), { description = "Next window in group" })
hl.bind("ALT + SUPER + SHIFT + TAB", hl.dsp.group.prev(), { description = "Previous window in group" })


-- Window navigation for grouped windows

hl.bind("ALT + CTRL + LEFT", hl.dsp.group.prev(), { description = "Move grouped window focus left" })
hl.bind("ALT + CTRL + RIGHT", hl.dsp.group.next(), { description = "Move grouped window focus right" })


-- Scroll through a set of grouped windows with ALT + SUPER + scroll

hl.bind("ALT + SUPER + mouse_down", hl.dsp.group.next(), { description = "Next window in group" })
hl.bind("ALT + SUPER + mouse_up", hl.dsp.group.prev(), { description = "Previous window in group" })


-- Activate window in a group by number

hl.bind("ALT + SUPER + code:10", hl.dsp.group.active({ index = 1 }), { description = "Switch to group window 1" })
hl.bind("ALT + SUPER + code:11", hl.dsp.group.active({ index = 2 }), { description = "Switch to group window 2" })
hl.bind("ALT + SUPER + code:12", hl.dsp.group.active({ index = 3 }), { description = "Switch to group window 3" })
hl.bind("ALT + SUPER + code:13", hl.dsp.group.active({ index = 4 }), { description = "Switch to group window 4" })
hl.bind("ALT + SUPER + code:14", hl.dsp.group.active({ index = 5 }), { description = "Switch to group window 5" })
