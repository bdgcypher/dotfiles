-- Cypher-shell launcher

-- The launcher is a full-screen layer surface drawing a centred box, so no_anim
-- makes the overlay appear instantly instead of animating in. Match on the exact
-- namespace so the bar (quickshell:cypher-shell) is unaffected.
hl.layer_rule({
    match   = { namespace = "quickshell:launcher" },
    no_anim = true,
})
