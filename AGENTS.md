# AGENTS.md

Instructions for AI coding agents working in this repository.

## What this is

Personal Arch Linux dotfiles, managed as GNU Stow packages. The desktop is
**Hyprland** (configured in Lua) plus **`hayami-shell`**, a Quickshell-based shell
that provides the bar, launcher, notifications and OSD in a single process.

## The one rule that matters

**Never edit anything under `$HOME/.config` (or any other stowed path) directly.**

Every config here is symlinked into `$HOME` by stow. An edit made through
`$HOME/.config/...` writes through the symlink and looks like it worked, but it
bypasses the repo layout. Always edit the file under its package directory in the
repo, then apply it:

```bash
cd ~/.dotfiles
stow -R -t "$HOME" <package>   # e.g. stow -R -t "$HOME" hypr
```

The top-level directory name **is** the stow package name (`hypr/`, `quickshell/`,
`bin/`, `ghostty/`, `btop/`, ...).

## Layout

| Path | What it is |
| --- | --- |
| `bin/.local/bin/` | every command: `hayami-*`, `screen-record`, `theme-mode`, ... |
| `quickshell/.config/quickshell/hayami-shell/` | the shell — `shell.qml`, `Bar*.qml`, `modules/`, `launcher/`, `notifications/`, `osd/`, `scripts/`, `menus/` |
| `hypr/.config/hypr/` | `hyprland.lua`, `bindings/`, `apps/`, `looknfeel.lua`, `default-apps.lua` |
| `scripts/` | installer and tooling — **not stowed** |
| `system/` | files copied into `/etc` by `setup_services.sh` — **not stowed** |
| `rust/` | Cargo workspace, built into `~/.local/bin` — **not stowed** |

`stow_configs.sh` excludes: `scripts`, `system`, `rust`, `mouseless`, `yay`,
`gh`, `bitwarden`, `mozilla`.

## The companion documents

This file is the map. These are the details, and each is worth reading before
the kind of work it covers:

| File | Read it before |
| --- | --- |
| `SKILLS.md` | adding anything to the shell: bar modules, popouts, menus, keybinds, the rule that no colour is written by hand, and the **"rebuild a plugin natively"** skill for a feature that came from somewhere else |
| `VERIFY.md` | deciding whether a change actually landed — and the two failures here that are silent |
| `THEME.md` | changing anything themed, or debugging a palette that did not apply |
| `BINDS.md` | adding a keybind or a menu entry (it lives in three places) |
| `BASH.md` | writing a script, and the traps in this shell that fail quietly |
| `LAUNCHER.md` | adding or debugging a launcher provider |
| `SURFACES.md` | adding a whole subsystem (state singleton, IPC target, surface, layer rule) |

## Command surface

The shell is driven entirely over its IPC socket by a family of commands, so
keybinds, menu entries and scripts never need to know how it is built.

| Command | Drives | IPC target |
| --- | --- | --- |
| `hayami-shell` | lifecycle: `start`, `stop`, `restart`, `reload`, `status`, `logs` | — |
| `hayami-bar` | bar edge, module toggles, clusters, keyboard mode | `bar` |
| `hayami-menu` | the launcher | `launcher` |
| `hayami-notify` | notification centre, DND, actions | `notifications` |
| `hayami-osd` | volume/brightness/playerctl OSD, custom messages | `osd` |
| `hayami-tray` | pop the system tray panel out | `tray` |
| `hayami` | dispatcher over all of the above, plus `status`, `reload`, `agent`, `doctor` | — |

`hayami <group> <args...>` forwards to `hayami-<group> <args...>`. Prefer the
`hayami` form in new code: it is the documented entry point and the one that
stays stable if the commands are renamed.

## Verifying a change

There is no build step. Verify the way each layer is actually reloaded:

| Change | How to apply / check |
| --- | --- |
| QML in `hayami-shell/` | `hayami-shell reload`, then read `hayami-shell logs` |
| Menu TOMLs | `hayami-menu --refresh` (the launcher reads a baked cache) |
| `hypr/*.lua` | `hyprctl reload` |
| Shell scripts | `bash -n <file>` |
| Anything stowed | `stow -R -t "$HOME" <package>` first, then reload |

`hayami reload` does the first three in the order that matters: **menus, then
Hyprland, then the shell**.

QML is **not** type-checked. `bash -n` is the only cheap static check for
scripts; `luac -p` is the equivalent for the Hyprland Lua; for Python, parse
with `python3 -c "import ast; ast.parse(open(f).read())"` — do not write
`__pycache__` into the tree. `VERIFY.md` has the full matrix, the checks that
catch a silent failure, and how to drive the shell to test a change live.

A QML file that fails to parse does **not** always say "error" in the log, and a
module that fails to load takes its whole subtree with it (the panel's rows, its
keys, the layer surface — all silently gone while the bar looks fine). Grep the
log for the load failure itself, which is what actually appears:

```bash
strings "$(ls -t /run/user/$UID/quickshell/by-id/*/log.qslog | head -1)" \
  | grep -iE "caused by|unavailable|Expected token|qml:[0-9]+|is not a type"
```

Then confirm the component is in the load list (`AgentPanel 1.0 AgentPanel.qml`)
and that its surface actually maps (`hyprctl layers -j` is keyed by monitor
then level — see the worked query in `VERIFY.md`). A clean-looking bar is not
evidence that a panel loaded.

## Conventions

- **QML** uses **tabs** for indentation and leans on long explanatory comments
  that say *why*, not what. Match that voice.
- **Hyprland** config is Lua; bindings are `hl.bind("<KEYS>", hl.dsp.exec_cmd(...), { description = "..." })` in `bindings/*.lua`, split by topic.
- **Dispatching from a script is Lua too.** This Hyprland parses `hyprctl dispatch`'s
  argument as Lua, so the older string form is a syntax error and exits **7**:
  `hyprctl dispatch focuswindow address:0x...` does nothing. Use `hyprctl eval`
  with an `hl.dsp.*` dispatcher instead, the way `hypr-firefox-pwa` and
  `hayami-agent` do:
  `hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:0x...' }))"`.
  A selector that matches nothing is a **warning** and still exits 0 — check what
  it printed, not its status.
- **Shell scripts** are `bash` with `set -uo pipefail` (not `-e` where a failure
  is expected), and user-facing commands print usage to **stderr**.
- **Menus** are TOML in `hayami-shell/menus/`; entries call `hayami-*` commands.
- **Colours are never written by hand.** Everything the shell draws comes from
  `pal`, fed live from pywal's `colors-quickshell.json` by `BarPalette.qml`, so a
  wallpaper change re-tints the shell with no reload. A new colour role is added
  to `BarPalette.qml`; `Theme.js` is geometry and behaviour, not colour. See
  `SKILLS.md`.
- Layer namespaces are the bare `quickshell:*` set (`bar`, `launcher`, `osd`,
  `notifications`, `vpn`, ...). `hypr/apps/*.lua` match on them.

## State and persistence

Runtime state lives in `$XDG_STATE_HOME/hayami-shell/` — never in the repo:

- `bar.json` — bar edge, hidden modules, calendar preferences.
- `agent.json` — cached Freebucks/agent reading (see below).

The defaults in QML are the source of truth for a fresh machine; the state file
only records what the user changed.

## Freebuff agent data (internal API)

The agent bar module reads local session state, then a **read-only** Freebuff API:

- Local live sessions: `~/.config/manicode/freebuff-live-<pid>.json`
  (`{instanceId, model, ownerPid, expiresAt}`) — **one per running agent**, and
  several can be live at once, each in its own directory. `agent-status.sh`
  reads them all, and matches each to its Hyprland window by walking the process
  chain (`hl.dsp.focus` needs an address; the window's pid is an *ancestor* of
  the CLI's, since the CLI runs under a terminal).- Turn state: `projects/<basename of the session's cwd>/chats/*/run-state.json`,
  read for two things, both structural:
  - `output.type` — `lastMessage` is the **only** value a completed run leaves
    behind, so it is what a finished turn is read from. `error` is written
    mid-run too, which is why it is not.

  That is the whole of the turn state. There is deliberately **no** "blocked on
  a question" state, because nothing the CLI writes can carry one: while a
  question is open `run-state.json` is frozen between steps, so the tool call and
  its answer land in a single write and an unanswered call is never visible.
  Measured, not assumed — a 68-second wait produced *no writes at all*, and
  `calls`/`answered` then both went 2→3 together. Nor is a tool call the last
  entry while a question is open (emitting it is followed by a `user` message
  carrying the question), and nothing else distinguishes the two: `log.jsonl` gets
  no record until the step ends, the window title is static, `wchan` is
  `do_epoll_wait` throughout, CPU time keeps climbing while blocked, and there is
  no CLI status command or IPC socket. A workaround that had the agent declare it
  was built and then removed — it depended on the agent cooperating, which does
  not hold in every project.

Every session is in one of **two** states, derived in `agent-status.sh` and
carried on each session as `status`:

| status | means | colour |
| --- | --- | --- |
| `working` | a run is in progress | `pal.working` |
| `finished` | turn over, waiting to be read | `pal.finished` |

Both roles are **fixed** in `BarPalette.qml`, not pywal's, for the same reason
`alert` is: each carries a fixed meaning, so a wallpaper must not be able to
repaint one state as the other — a warm image putting its own hue where "finished"
goes would make a turn waiting to be read look like something else.

The bar's badge (`AgentIndicator` → BarItem's `dot`) reports the **most urgent**
state any session is in, in the order **working → finished**: a run under way
first, then a turn that is merely over. Idle wears no badge.

The **same order sorts `sessions`** in the reading, so the top row of the card's
list is always the one the badge is reporting, and opening the card marks it.
Each row carries its model, its directory and a dot in that session's colour,
and the selected session's state is spelled out again in the readings below as a
`Status` row. Under the heading the card names only the provider: the state is
carried by the badge and the row dots, not restated in the heading. The sort is
stable, so sessions sharing a state keep the order they were read in.

The notification bell's own dot is a different signal in the same colour as
`alert`; it is not the agent's.

## Do not

- Do not edit `system/` files expecting them to apply — they are copied to `/etc`
  by `scripts/setup_services.sh`, which needs sudo.
- Do not commit `rust/target/`, `__pycache__/`, or anything under
  `~/.config/manicode/`.
- Do not run `git push`, `git commit`, or the installer's sudo steps without
  being asked.
