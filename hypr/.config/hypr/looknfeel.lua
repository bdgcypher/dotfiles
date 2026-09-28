-- Look and feel

-- ── the bar's reserved strip ─────────────────────────────────────────────────
--
-- The bar sits on whichever edge it has been moved to (drag it, or pick from
-- Setup -> Bar -> Position in the launcher), and it reserves a strip of the
-- screen on that edge for itself: the reservation is a gap, not a layer-shell
-- exclusive zone, which is how this desktop has always done it -- the top gap
-- here used to be `monitor=,addreserved,40,0,0,0`.
--
-- Where the bar is lives in the state cypher-shell writes, so this reads it
-- rather than hard-coding an edge. That is what keeps a reload honest: reload
-- the config and the reservation is recomputed for wherever the bar actually
-- is, instead of snapping back to the top.
-- The reserved strip is measured rather than assumed, because the bar is not the
-- same size on every edge: 26px tall across the top or bottom, but 32px thick
-- down a side (the modules turn a quarter and stack -- see Theme.js, which these
-- three mirror). Add the 6px the bar keeps from the screen edge and the same 8px
-- of air past it, and the strip is 40 across and 46 down a side. Reserving 40 on
-- a side bar would leave the windows 2px off it instead of 8, which is what the
-- 46 is for.
local BAR_MARGIN = 6
local BAR_HEIGHT = 26
local BAR_THICKNESS = 32
local BAR_CLEARANCE = 8
local SIDE_GAP = 12 -- the other three edges keep the plain window gap

local function bar_edge()
    local file = io.open(os.getenv("HOME") .. "/.local/state/cypher-shell/bar.json", "r")
    if not file then
        return "top"
    end
    local state = file:read("a")
    file:close()

    local edge = state:match('"position"%s*:%s*"(%a+)"')
    if edge == "top" or edge == "bottom" or edge == "left" or edge == "right" then
        return edge
    end
    return "top"
end

-- Global on purpose. `hyprctl eval "cypher_bar_gaps('left')"` is how cypher-shell
-- applies a move the moment it happens -- no reload, no waiting -- so this call
-- and the one below share one definition of the numbers rather than each keeping
-- its own copy. With no argument it reads the saved edge.
function cypher_bar_gaps(edge)
    if edge ~= "top" and edge ~= "bottom" and edge ~= "left" and edge ~= "right" then
        edge = bar_edge()
    end

    local along = BAR_MARGIN + BAR_HEIGHT + BAR_CLEARANCE
    local across = BAR_MARGIN + BAR_THICKNESS + BAR_CLEARANCE

    local gaps = { top = SIDE_GAP, right = SIDE_GAP, bottom = SIDE_GAP, left = SIDE_GAP }
    gaps[edge] = (edge == "left" or edge == "right") and across or along
    hl.config({ general = { gaps_out = gaps } })
end

cypher_bar_gaps()

hl.config({
    general = {
        -- Gaps between windows and borders
        gaps_in     = 6,
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
