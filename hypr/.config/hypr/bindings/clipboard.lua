-- Copy / Paste

hl.bind("SUPER + C", hl.dsp.send_shortcut({ mods = "CTRL", key = "Insert", window = "activewindow" }))

hl.bind("SUPER + V", hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert", window = "activewindow" }))

hl.bind("SUPER + X", hl.dsp.send_shortcut({ mods = "CTRL", key = "X", window = "activewindow" }))

hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd("walker -m clipboard"))
