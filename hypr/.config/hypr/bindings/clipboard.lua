-- Copy / Paste

-- The universal three. All three go through a script, because none of them is a
-- single chord that works everywhere, and a keybind cannot ask what the focused
-- window is.
--
-- SUPER+V picks its chord from the window: a terminal gets Ctrl+Shift+V, which
-- every terminal emulator binds, and everything else gets Shift+Insert, which is
-- the X11 standard paste that GTK and Qt bind. An image on the clipboard is a
-- different problem with a different answer, and it is answered where the image
-- is actually chosen -- the history menu (SUPER+CTRL+V), whose entries go
-- through the same clipboard-paste.
hl.bind("SUPER + V", hl.dsp.exec_cmd("clipboard-paste"))

-- Copy and cut go through a script rather than straight to a chord, because no
-- single chord is universal for them. See clipboard-action.
hl.bind("SUPER + C", hl.dsp.exec_cmd("clipboard-action copy"))

hl.bind("SUPER + X", hl.dsp.exec_cmd("clipboard-action cut"))

hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd("hayami-menu -m clipboard"))
