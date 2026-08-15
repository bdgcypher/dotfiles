-- DaVinci Resolve
-- NOTE: this file was NOT sourced by apps.conf in the hyprlang setup and is
-- kept here (converted) for completeness only.

-- Focus floating DaVinci Resolve dialog windows
hl.window_rule({
    match        = { class = ".*[Rr]esolve.*", float = true },
    stay_focused = true,
})
