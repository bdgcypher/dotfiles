-- Look and feel

hl.config({
    general = {
        -- Gaps between windows and borders
        gaps_in     = 6,
        gaps_out    = { top = 40, right = 12, bottom = 12, left = 12 },
        border_size = 2,

        -- Window colors
        col = {
            active_border = border_active,
        },
    },

    decoration = {
        rounding = 8,
    },

    layout = {
        -- Avoid overly wide single-window layouts on wide screens
        single_window_aspect_ratio = { 16, 10 },
    },
})
