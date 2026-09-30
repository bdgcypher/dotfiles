# BINDS.md

How a new key, or a new menu entry, is added — all the places it has to appear,
and how to check it.

A key lives in **two** files and a **third** if it also belongs in a menu. Only
editing the first is the usual half-done state: the key works, and the
keybinds overview silently lies about it.

## Which file the bind goes in

`hypr/.config/hypr/bindings/` is split by topic, and a key goes in the file that
matches what it does, not the one that has the free space:

| File | Holds |
| --- | --- |
| `applications.lua` | anything that starts an app or a session (`SUPER + SHIFT + A`) |
| `utilities.lua` | shell utilities, the launcher, the agent panel, the bar (`SUPER + A`) |
| `media.lua` | volume, brightness, playback — the media keys |
| `clipboard.lua` | copy/paste into the focused window |
| `tiling.lua` | layout, focus direction, window movement |

The form is always:

```lua
hl.bind("SUPER + A", hl.dsp.exec_cmd("hayami agent panel"), { description = "Agent panel" })
```

- **Keys** are `SUPER`/`ALT`/`CTRL`/`SHIFT` joined by `+`, upper case, in the
  order the config uses everywhere else. `RETURN`, not `Enter`; `SLASH`, not
  `/`.
- **`description`** is what `hyprctl binds` prints and what makes the list
  readable — sentence case, naming the *thing* not the action ("Agent panel",
  "Coding agent", "Passwords"). A bind that does shell plumbing still gets one.
- **Options** beyond `description`: `{ locked = true }` to work on the lock
  screen, `{ repeating = true }` for keys that autorepeat (volume, brightness).
  Media keys use both.
- **The command is a `hayami …` one.** No binding calls `qs ipc` or
  `hyprctl dispatch` directly — that is the point of the command family, so the
  shell can be rebuilt behind a stable name. `hayami <group> <args>` forwards to
  `hayami-<group>`, so a new verb needs no change to the dispatcher.

### The Lua-dispatch trap

Anything that dispatches *from a script or a Process* must use the Lua form,
because this Hyprland parses `hyprctl dispatch`'s argument as Lua:

```bash
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:0x…' }))"
```

The plain `hyprctl dispatch focuswindow address:0x…` is a syntax error, exits
**7**, and does nothing — which looks exactly like "the key is not bound". A
selector matching nothing is a *warning* that still exits 0, so check the text
it printed. The stubs are at `/usr/share/hypr/stubs/hl.meta.lua`; `hl.dsp.focus`
takes only `direction, monitor, window, urgent_or_last, last`.

### Choosing the key

The convention that settled itself with the agent module: **the bare key is the
frequent action, the launch row is the rare one.**

- `SUPER + A` — open the agent panel. A glance at what is running, mid-task.
- `SUPER + SHIFT + A` — start a session. Deliberate, and not hit by accident.

The session bind is on SHIFT because that is the row this desktop launches
things from: `SUPER+SHIFT` is the file manager, the browser, the editor,
Obsidian and Slack, and an agent session is another thing you launch rather
than a mode you toggle. It used to be `SUPER + CTRL + A`, which put it in a row
of its own for no reason and made the pair harder to remember than the two keys
had any right to be.

Put the reasoning in a comment above the bind. A keybind file is read by the
person deciding what to put their thumb on next, and "why this and not that" is
the part they cannot infer from the key.

## The keybinds overview (`menus/keybinds.toml`)

A flat, ordered list; there are no sections and no weights. The format is fixed
so the columns line up:

```toml
text = "Agent Panel                                →          SUPER + A"
icon = ""
actions = { "default" = "hayami-menu --close" }
```

- The **label is padded to 43 characters**, then `→`, then ten spaces, then the
  keys. Count it — the alignment is the whole point of the file.
- `icon = ""` on every row: these are not icons, they are a table.
- `actions = { "default" = "hayami-menu --close" }` — the overview closes the
  launcher when you pick a row, because the key has already fired by then.
  Almost every row is that; the one that is not ("Bar keyboard") is a row that
  *does* the thing rather than just pointing at a key. A row saying something
  else with no reason is a row that does nothing.

Both files are read at different times: the bind is live after `hyprctl reload`,
the row only after the menu cache is rebuilt.

## Menu entries (`menus/*.toml`)

The schema, from `menus/theme.toml` and `menus/main.toml`:

```toml
name = "system/theme"              # the provider id: menus:system/theme
name_pretty = "System → Theme"     # the breadcrumb
icon = "󰏘"                 # the menu's own glyph

[[entries]]
text = "Set Random Wallpaper"
icon = " "                  # a Nerd Font glyph plus a trailing space
actions = { "default" = "~/.local/bin/set-random-wallpaper" }
weight = 90                          # higher = earlier; the file is authored in order
```

- **Naming** is the path: `system/setup/bar/toggle` is
  `menus:system/setup/bar/toggle`, and the `menus:` prefix is how a keybind or
  another entry opens it (`hayami-menu -m menus:system/power --width 250`).
  Slashes and hyphens have both been used; the query placeholders in
  `Query.js` list the ones that must resolve, so **a new menu needs a
  placeholder added there too** or it opens with a raw id as its title.
- **Weights** step by ten (`100, 90, 80, 70`), or by five when an entry is
  squeezed in next to an existing one (the agent's toggle sits at 92).
- **Icons** are literal Nerd Font glyphs in the TOML, each with a trailing
  space. Where the same glyph is also in `Icons.js`, write it as a `\U000XXXXX`
  escape with a comment saying so (`menus/bar-toggle.toml` does this for the
  agent) — one codepoint, spelled once.
- **Actions** are shell commands, so a menu entry can do anything a script can.
  They should call a `hayami-*` command or a purpose-named script, never inline
  logic.

## The baked cache

`scripts/menus-json.py` flattens every `menus/*.toml` into
`$XDG_RUNTIME_DIR/quickshell-hayami-shell-menus.json`, which is what the launcher
actually reads. It is written **atomically** (the launcher watches it; a
half-written file would be a truncated menu tree).

Editing a TOML does nothing until the cache is rebuilt:

```bash
hayami-menu --refresh        # or: hayami reload, which does this plus hypr plus the shell
```

Check the result without opening the launcher:

```bash
jq -r '.. | objects | select(.text? and (.text|test("Agent"))) | .text' \
  "$XDG_RUNTIME_DIR/quickshell-hayami-shell-menus.json"
```

## Checking a new bind

```bash
stow -R -t "$HOME" hypr && hyprctl reload
hyprctl configerrors                       # empty = parsed cleanly
hyprctl binds -j | jq -r '.[] | select(.modmask>0) | "\(.modmask) +\(.key) -> \(.description)"'
```

`modmask` is a bitfield, and the two halves are separate: the low nibble is the
modifiers, the high byte is the SUPER/ALT/CTRL flags. Read off the live
compositor rather than guessed at — `hyprctl binds -j | jq -r '.[].modmask' |
sort -un`:

| mask | means | | mask | means |
| --- | --- | --- | --- | --- |
| 8 | ALT | | 64 | SUPER |
| 9 | ALT + SHIFT | | 65 | SUPER + SHIFT |
| 12 | ALT + CTRL | | 68 | SUPER + CTRL |
| | | | 72 | SUPER + ALT |
| | | | 73 | SUPER + ALT + SHIFT |
| | | | 76 | SUPER + CTRL + ALT |

This table was wrong before it was written down: it had 65 as SUPER+ALT and no
SUPER+SHIFT row at all, which is how `SUPER + SHIFT + A` came to be described as
something to look for under a mask nothing in the config used. So
`SUPER + SHIFT + A → Coding agent` is mask **65** — the same as the Editor, the
Browser and Slack beside it, which is the check worth making: if the new bind's
mask does not match its new row's siblings, it is not on the row you think. Then
press it (`wtype -k a` with SUPER held is fiddly — just use the key) and see
what `VERIFY.md` says about driving and observing the shell.

For a menu entry, the check is the `jq` above plus opening it: `hayami-menu -m
menus:<name>`. For a keybinds row, refresh the cache and look for it there.
