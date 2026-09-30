# THEME.md

How a wallpaper becomes colours, everywhere.

One image is the only theme input. Everything else — the bar, the launcher, the
notifications, the OSD, the terminal, the GTK apps, the TUI tools, the
lock screen — is a *rendering* of a palette pywal generates from that image.
This is the whole system:

```
~/dotfiles/wallpapers/Wallpapers/<image>
        │
        │  apply-wallpaper [--rebalance|--no-rebalance] <image>
        ▼
   rebalance-pywal-colorscheme  (rust/, "rebalanced")
        or  wal -i -n --cols16 lighten  ("original")
        │
        ▼
   ~/.cache/wal/*            ← every consumer reads from here
        │
        ├── colors-quickshell.json ─▶ BarPalette.qml ─▶ pal ─▶ the whole shell
        ├── colors-hyprland.lua   ─▶ hyprland.lua / hyprlock / animations
        ├── colors-gtk.css        ─▶ GTK3 (hash-suffixed theme) + GTK4
        ├── colors-ghostty.conf   ─▶ ~/.config/ghostty/themes/pywal
        ├── colors-hyprlock.conf  ─▶ the lock screen
        ├── colors-discord.css    ─▶ copied into the vesktop theme
        ├── btop.theme, colors-cava.conf, colors-gazelle.toml,
        │   colors-bluetui.toml, colors-walker.css, obsidian.css,
        │   pywal.kvconfig, pywal.svg   ─▶ the rest
```

## The two modes

`apply-wallpaper` runs one of two generators:

- **original** — `wal -i <image> -n --cols16 lighten`. pywal's own 16-colour
  `lighten` scheme.
- **rebalanced** — `rebalance-pywal-colorscheme <image>`, a Rust binary built
  from `rust/` and installed into `~/.local/bin` by `scripts/stow_configs.sh`.
  It rebalances pywal's result so the accent and the mid-tones sit closer
  together; it is a wall-of-colour difference, not a hue difference.

Which is the *default* is a user setting in
`~/.config/theme/default_theme_mode` (`theme-mode rebalanced`, or
`theme-mode toggle`). Which was *actually applied* is written to
`current_theme_mode` on every run. `toggle-theme-mode` flips the current one and
reapplies; when `current_theme_mode` is missing it detects the mode by hashing
the live palette and comparing it against a freshly computed rebalanced one.

## What `apply-wallpaper` does, in order

1. Repoints `~/.config/theme/current_wallpaper` at the image (a symlink —
   `readlink -f` it to get the real path).
2. Sets the wallpaper with `swww`, or `awww`, with an `any` transition.
3. Generates the palette (rebalanced or original).
4. Writes `current_theme_mode`.
5. Reloads consumers, in this order: `hyprctl reload` first (everything else
   is a client of it), then `pkill -USR2` for btop and cava, `obsidian reload`
   if it is running, `hayami-notify -rs` for the notification centre, then the
   vesktop CSS copy, then GTK3/GTK4, then the icon theme.
6. The OSD is deliberately absent from that list: it reads the palette through
   the shell, which watches the file, so it re-tints on its own.

## The shell specifically

`BarPalette.qml` is the shell's only source of colour. It is a `QtObject` with
a `FileView` on `~/.cache/wal/colors-quickshell.json` with `watchChanges: true`,
so it re-parses and repaints the bar, the launcher, the notifications and the
OSD **the moment pywal writes the file**. There is no reload step for a theme
change and adding one would be a bug.

It maps the palette to four roles and exposes all sixteen:

| `pal.*` | pywal key | The shell's use |
| --- | --- | --- |
| `background` | `background` | surfaces, the badge's inset border |
| `foreground` | `foreground` | every glyph and label by default |
| `accent` | `cursor` | the shell's accent |
| `muted` | `color8` | quiet text |
| `colors[i]` | `color0`..`color15` | anything wanting a specific slot |
| `alert` | *(hardcoded `#a55555`)* | recording, dictation, "needs you" — **not** the wallpaper |

`Bar.qml`'s `accent` is `pal.colors[3]`, and it is the one colour every list in
the shell marks focus with. The fallback colours in `BarPalette.qml` exist only
so the shell renders before pywal has ever run on a fresh machine.

The other two subsystems resolve the same palette: `notifications/NotifColors.qml`
maps swaync's `@color1`/`@color5`/… names onto `pal.colors[]` (once, because the
two swaync stylesheets disagreed with each other), and `osd/OsdTheme.js` plus
`modules/Theme.js` are geometry and type only.

**Rules for anything you add to the shell are in `SKILLS.md`** — the short
version: no literal colour outside `BarPalette.qml`, a new role is added there
with a fallback, tints are derived with alpha rather than picked, and `alert`
stays hardcoded.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| The bar did not re-tint | `colors-quickshell.json` missing, or older than the wallpaper | `ls -l ~/.cache/wal/colors-quickshell.json`; re-run `apply-wallpaper`; if the file is fresh and the bar is still stale, `hayami-shell reload` |
| The bar re-tinted, GTK did not | GTK3 caches parsed themes *by name*; the same name is never re-read | `apply-wallpaper` builds a per-wallpaper theme named `adw-gtk3-pywal-<md5>`, so the name changes every palette. If you hand-edited `gtk-3.0/gtk.css` expecting a hot reload, that will not work — it is read once at launch |
| Icons went missing during a theme change | the oomox icon theme was rebuilt in place, and GTK3 apps abort when the theme vanishes mid-rebuild | already handled: `apply-wallpaper` builds into `oomox-pywal.new` and swaps atomically. Keep it that way if you touch it |
| The theme is the wrong "flavour" | default vs applied drifted | `theme-mode` prints both; `toggle-theme-mode` re-applies the other |
| A new app does not theme | it is not a pywal template consumer | see below |
| A GTK app is light | the theme fell back | `apply-wallpaper` warns on stderr when `colors-gtk.css` is missing or `/usr/share/themes/adw-gtk3-dark` is not found, and falls back to no hot reload |

The rendered files are all in `~/.cache/wal/`, so any of this can be checked
without guessing:

```bash
ls -l ~/.cache/wal/                    # every consumer's output, with timestamps
jq -r '.accent, .background' ~/.cache/wal/colors-quickshell.json
```

## Theming something that is not the shell

If a new application should follow the wallpaper, it is a **pywal template**,
not a shell edit and not a hardcoded colour:

1. Add `wal/.config/wal/templates/colors-<app>.<ext>` with pywal's
   `{color0}`…`{color15}`, `{background}`, `{foreground}`, `{cursor}`
   placeholders. Copy the shape of `colors-ghostty.conf` or
   `colors-hyprland.lua`.
2. Re-run `apply-wallpaper` to render it.
3. Point the app at it. If the app reads from a path *inside* `~/.cache/wal/`,
   a symlink made by the post-stow hook in `scripts/stow_configs.sh` is the
   established pattern (that is how ghostty, cava, btop and Kvantum are wired).
4. If the app needs a nudge to re-read, add it to the reload list in
   `apply-wallpaper` in the same order as the others — Hyprland first, always.

A colour that **only the shell needs** never needs a template. That is the
distinction: templates are how one palette reaches several processes; `pal` is
how one palette reaches every module in this one.
