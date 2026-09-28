-- Cypher-shell bar

-- The bar is a layer surface whose geometry changes outright when it moves to
-- another edge: a top bar is 1721x26 and a left one is 32x958, so the size
-- changes while the anchors do. Hyprland's `layers` animation (enabled by
-- default) animates a layer between its old and new geometry, drawing the
-- surface into the rectangle in between as it goes -- so for the ~200ms of the
-- move the bar's own buffer, chrome first, is stretched across the desktop as a
-- grey slab that grows and narrows before the bar appears on its new edge.
--
-- no_anim lands the geometry change in one frame. That is also what the move
-- wants: the bar standing on the new edge is the feedback, and no_anim is the
-- same fix this config already applies to the launcher and to hyprshot's
-- selection overlay.
hl.layer_rule({
    match   = { namespace = "quickshell:cypher-shell" },
    no_anim = true,
})
