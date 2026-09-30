# VERIFY.md

How to prove a change to this desktop actually landed.

There is no build step and no test suite here, and that is not the same as there
being nothing to check. The reason this file exists is that **the two most
common failures in this shell are silent**: a QML file that does not parse
still leaves a bar that looks fine, and a Hyprland dispatch that does nothing
still exits 0. "It looked right" is not evidence.

Read `AGENTS.md` for the rules; read this for the checking.

## Apply, then reload

Nothing is read from the repo at runtime — every path is a stow symlink, so an
edit under `~/.config` writes *through* to the repo (fine) but an edit to a
stow-ignored file never reaches `$HOME` at all. Always:

```bash
cd ~/.dotfiles && stow -R -t "$HOME" <package>    # quickshell, hypr, bin, wal, ...
```

Then reload the one layer that reads it. Quickshell watches its own `.qml` and
picks up most edits by itself; `hayami-shell reload` is a full restart and
exists for the cases the watcher misses (a restow that replaced files, a
regenerated palette, a change under `scripts/`).

| You changed | Apply | Reload | Check |
| --- | --- | --- | --- |
| `hayami-shell/**/*.qml` | `stow … quickshell` | `hayami-shell reload` | the load list + the grep below |
| `modules/Theme.js`, `Icons.js` | `stow … quickshell` | `hayami-shell reload` | same |
| `hayami-shell/scripts/*` (probes) | `stow … quickshell` | nothing — the next 5s tick runs the new one | the reading on the bar changes |
| `menus/*.toml` | `stow … quickshell` | `hayami-menu --refresh` | the baked cache contains it |
| `hypr/**/*.lua`, `*.conf` | `stow … hypr` | `hyprctl reload` | `hyprctl configerrors` is empty |
| `bin/.local/bin/*` | `stow … bin` | nothing | `command -v <name>`; run `--help` |
| `wal/…/templates/*` | `stow … wal` | re-run `apply-wallpaper` (see `THEME.md`) | the rendered file changed |
| `$XDG_STATE_HOME/hayami-shell/*.json` | — | nothing — state is read at change, not at load | the reading matches |

`hayami reload` does the first three in the order that matters — **menus, then
Hyprland, then the shell** (Hyprland before the shell, so the bar's reserved
strip is final before the bar is a surface on it). Use it when you have touched
more than one of them.

## The static checks that exist

There are only three, and all three are cheap:

```bash
bash -n <script>                                  # every .sh
luac -p <file.lua>                                # every hypr lua file
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" <file.py>
```

`luac -p` parses without running anything, which matters for a config that is
Lua executed by the compositor: a syntax error there takes the whole config with
it, and `hyprctl reload` will not always say so. For Python, parse rather than
import — importing writes `__pycache__` into the tree, which is gitignored but
still litter.

`hyprctl configerrors` is worth running after any `hyprctl reload`: it is empty
on a healthy config and is the only place a *warning* from the reload surfaces.

## Did the QML even load?

A QML parse failure does **not** contain the words `error`, `warning`,
`undefined`, `cannot` or `unable`. Grepping for those reports "clean" on a
component that is dead. Grep for the load failure itself:

```bash
strings "$(ls -t /run/user/$UID/quickshell/by-id/*/log.qslog | head -1)" \
  | grep -iE "caused by|unavailable|Expected token|qml:[0-9]+|is not a type"
```

`hayami-shell logs` follows the same file if you would rather watch it live
(it prints the path on stderr first). Then two positive checks, because a clean
log is not the same as a loaded component:

1. **Is it in the load list?** `AgentPanel 1.0 AgentPanel.qml` in the log means
   the file parsed and instantiated. Its absence with no error usually means it
   was never reached — a `visible: false` parent, or a component not referenced
   by anything.
2. **Is its surface mapped?** For a layer surface:
   ```bash
   hyprctl layers -j | jq -r '.[].levels[][]? | select(.namespace=="quickshell:agent") | "\(.namespace) \(.w)x\(.h)"'
   ```
   A parsed component whose surface is not mapped is a component that drew
   nothing — the flag is false, the geometry is off-screen, or it is behind
   another surface.

   **The nesting matters.** The JSON is keyed by monitor, then by level, then
   by an array of surfaces, and the sizes are `w`/`h`, not `width`/`height`:

   ```bash
   # every surface this shell owns, across every monitor
   hyprctl layers -j | jq -r '.[].levels[][]? | select(.namespace|startswith("quickshell")) | "  \(.namespace) \(.w)x\(.h)"'
   ```

   A flat `.[] | select(.namespace==…)` on that object matches nothing and
   prints nothing — which reads exactly like "the surface is not there" and sent
   this down a false trail once already. If a surface you can see on screen is
   "missing" from this check, suspect the query before you suspect the QML.

## Driving it

`wtype` synthesises real input, which is the only honest way to test a keymap,
a focus ring or a panel's own keyboard:

```bash
wtype -k j            # a key by name
wtype -k space
wtype -k Return
wtype -k Escape
wtype text "hello"    # literal text
wtype -k ctrl+a
```

Focus matters: a `wtype` goes to the focused window, so before testing a
panel's own keys, open it *with* the keybind (so the panel has the keyboard) and
afterwards put focus back where it was:

```bash
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:0x…' }))"
```

That is the Lua form and it is not optional. `hyprctl dispatch focuswindow
address:0x…` is a **syntax error** in this Hyprland and exits **7** having done
nothing. A selector that matches nothing is a *warning* and exits 0 — so check
what it printed, not its status:

```bash
out=$(hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:0x$addr' }))")
[ "$out" = ok ] || echo "focus did not land: $out"
```

## Reading live QML state

When a binding is not doing what you think, the fastest way to see the truth is
to have the component say it. Add a temporary timer to the thing you are
debugging, read it, then remove it:

```qml
Timer {
	interval: 1000
	running: true
	repeat: true
	onTriggered: console.log("debug badge", waitingDot.visible, waitingDot.width)
}
```

This beats a screenshot for anything numeric (`visible false`, `width 7`) and it
beats introspection, because there is no way to evaluate an expression in a
running Quickshell from outside. `console.log` lands in the qslog the greps
above already read.

## Screenshots: what does and does not work

- **Full-screen `grim` → `magick compare` is useless here.** The live terminal
  repaints between the two grabs, so every diff is non-zero and tells you
  nothing about your change.
- **A bar-strip crop is worse than nothing in the middle of the status
  cluster**: cpu and memory change every five seconds on their own.
- What does work: crop to the *static* part of the bar (the layout group on the
  left, or a panel that is open and idle), and crop a popout, which does not
  repaint while it is up.
- For geometry, prefer the compositor's own answer over a pixel count:
  `hyprctl layers -j` reports each surface's exact `w`/`h`/`x`/`y`, which is
  what a "does it fit?" question is actually about.

## The checks that catch their own class of bug

| Symptom | The check that settles it |
| --- | --- |
| The bar has no new module | `hyprctl layers -j` for `quickshell:bar`, then the load list |
| A panel does not open | Is the `BarState` flag set (`hayami-bar state`)? Is the surface mapped? |
| A key does nothing | `hyprctl binds -j` — is the bind even loaded, and is it the one you think? |
| A menu entry is missing | Is the row in `$XDG_RUNTIME_DIR/quickshell-hayami-shell-menus.json`? If not, `--refresh`. |
| The theme did not change | See `THEME.md` — the shell watches the palette file, so "did not re-tint" is a file problem |
| Nothing works at all | `hayami doctor`, then `hayami-shell status` |

`hyprctl binds -j` prints the modmask as a bitfield: `64` is SUPER on its own,
`68` is SUPER+CTRL. That is how you confirm a rebind took effect without
pressing anything:

```bash
hyprctl binds -j | jq -r '.[] | select(.modmask>0) | "\(.modmask) +\(.key) -> \(.description)"'
```

`hayami doctor` checks the things that break silently and leave no other
clue: every `hayami-*` on `PATH`, the shell running, and the shell holding
`org.freedesktop.Notifications` (a running shell that does not own that name
cannot show notifications, and nothing on screen says so).
