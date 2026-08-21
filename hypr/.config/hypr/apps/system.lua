-- System / floating windows

hl.window_rule({
    match = { tag = "floating-window" },
    float = true,
})
hl.window_rule({
    match  = { tag = "floating-window" },
    center = true,
})
hl.window_rule({
    match = { tag = "floating-window" },
    size  = "875 600",
})

hl.window_rule({
    match = { class = "(org.gnome.Evince|com.gabm.satty|imv|mpv)" },
    tag   = "+floating-window",
})
hl.window_rule({
    match = {
        class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors)",
        title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
    },
    tag = "+floating-window",
})
hl.window_rule({
    match = { class = "org.gnome.Calculator" },
    float = true,
})

-- No transparency on media windows
hl.window_rule({
    match = { class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv)$" },
    tag   = "-default-opacity",
})
hl.window_rule({
    match   = { class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv)$" },
    opacity = "1 1",
})

-- Popped window rounding
hl.window_rule({
    match    = { tag = "pop" },
    rounding = 8,
})

-- Prevent idle while open
hl.window_rule({
    match        = { tag = "noidle" },
    idle_inhibit = "always",
})
