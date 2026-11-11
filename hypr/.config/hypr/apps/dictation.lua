-- hayami-shell dictation glow

-- The glow follows the focused window, so its layer surface is resized and
-- re-anchored every time that window moves or another takes the focus.
-- Hyprland's `layers` animation (on by default) animates a surface between its
-- old and new geometry, drawing the old buffer into the rectangle in between --
-- so without this the glow would smear from one window to the next for the ~200
-- ms of the animation, and a glow that is supposed to track the window would be
-- visibly behind it. no_anim lands each move in one frame, the same fix the bar
-- and the launcher carry for the same reason.
--
-- The namespace is matched exactly; quickshell:bar and quickshell:launcher are
-- separate rules.
hl.layer_rule({
    match   = { namespace = "quickshell:dictation" },
    no_anim = true,
})
