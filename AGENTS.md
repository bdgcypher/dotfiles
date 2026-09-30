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
  the CLI's, since the CLI runs under a terminal).
- Turn state: `projects/<basename of the session's cwd>/chats/*/run-state.json`
  → `output.type`. `lastMessage` is the **only** value a completed run leaves
  behind — `error` is written mid-run too — so it, and only it, is what the bar's
  dot badge and the reading's `anyWaiting` mean by "waiting". The project
  directory is named after the last segment of the working directory and the
  most recently written state in it belongs to the session that is up; the lease
  file names neither. Only that one field is ever read (with `grep`, not `jq` —
  the file is megabytes of message history), and it is the one exception to the
  "no conversation content" rule above: the field is a state enum, the messages
  beside it in that file are never touched.
- `GET https://www.codebuff.com/api/v1/freebuff/session` →
  `freebucks.balance`, `freebucks.daily{limit,spent,remaining,resetAt}`,
  `freebucks.wallet.balance`, `accessTier`, `freebucks.prices` (per-model
  Freebucks/hour), `freebucks.offPeak`.
- `GET /api/v1/freebuff/streak` → `streak`, `todayUsed`, `freebucksDailyBonus`.
- Auth: `Authorization: Bearer <token>`, where the token is
  `~/.config/manicode/credentials.json` → `.default.authToken`.

Rules for this API:

1. **Read-only.** Do not call `POST /api/v1/freebuff/session/admission` — it
   reserves credits.
2. **Never print, log, echo or commit the token.** Read it at call time.
3. It is **undocumented and may change**. Keep all access in
   `hayami-shell/scripts/agent-status.sh`, handle `401` as "not logged in", and
   never let a failed call break the bar.
4. Cache responses (~60s) so polling does not hammer it.

The bar's agent popout lists every live session: **hjkl / arrows** move the
mark, **space / enter** (or a click on the row) focuses that session's terminal,
and escape or a click off the card puts it away. Selection lives in
`AgentPanel.qml`; the open/closed flag is `BarState.agentPanel` (`hayami-bar
agent toggle`), so the keybind, the module's click and the IPC verb agree. The
bar's badge (`AgentIndicator` → BarItem's `dot`, the same one the notification
bell uses) means *a session is waiting for you* — any one of them, since the
glyph stands for all of them — and the count beside the glyph is how many.

## Do not

- Do not edit `system/` files expecting them to apply — they are copied to `/etc`
  by `scripts/setup_services.sh`, which needs sudo.
- Do not commit `rust/target/`, `__pycache__/`, or anything under
  `~/.config/manicode/`.
- Do not run `git push`, `git commit`, or the installer's sudo steps without
  being asked.
