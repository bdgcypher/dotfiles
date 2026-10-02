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
  (`{instanceId, model, expiresAt, ownerPid}`) — **one per running agent**, and
  several can be live at once, each in its own directory. `agent-status.sh`
  reads them all, and matches each to its Hyprland window by walking the process
  chain (`hl.dsp.focus` needs an address; the window's pid is an *ancestor* of
  the CLI's, since the CLI runs under a terminal). The match is on the window
  title mentioning the provider, **case-insensitively** — a terminal left on the
  bare command line keeps a lowercase `freebuff` in its title.

  Every tab of a terminal shares that terminal's window pid, so walking up from
  two sessions lands on the same pid and the pool used to be handed out in
  whatever order Hyprland listed the windows — a coin toss, and clicking the row
  focused the wrong agent. The **title** settles it, because it is evidence of
  whether the session has spoken yet: a TUI that has run a step rewrites the
  title to `Freebuff: <what it is doing>`, and one that has not still has the
  title its terminal gave it, which for a session started by hand is the bare
  command name. So a window whose title is exactly the provider belongs to a
  session that has not run a step — precisely an `idle` one — and idle takes
  that window while everything else prefers a rewritten title, which cannot be
  swapped whichever order the sessions are read in.

  What is left is two sessions of the *same* kind in tabs of one terminal -- two
  working ones, both titled `Freebuff: <their own prompt>`. That is decidable
  too, because a title is not decoration: the TUI puts the prompt in it and the
  log records the prompt of every step, so a title is a *prefix* of one prompt
  in exactly one session's log, and asking which log contains it settles the
  question. Two things about that, both measured:

  - **The title lags.** It carries the last *completed* turn's prompt, not the
    current one, so while a turn is running it names the turn before it -- whose
    first step can be megabytes back past everything the current turn has
    logged. A short tail finds the current turn's prompt and not that one, so
    the whole log is searched when the tail misses. A fixed-string `grep -q`
    over a 5MB log is single-digit milliseconds, and it runs only in the
    ambiguous case.
  - **The needle is the title, not the prompt.** The search runs *from* the
    title into the log, never the other way round, so no prompt text is lifted
    out of the log into the shell. The needle is Hyprland's own state and is
    already on the terminal's title bar; the log is the haystack; `grep -q`
    answers yes or no and nothing else comes out. It is anchored on the
    `"prompt":"` that opens the field, so a match has to be a prompt and not the
    same words turning up in a tool result. A prompt containing a quote or a
    newline is escaped in the log and will not match, which costs a fall back to
    the tiers and nothing else.

  This is the one place in the script that reads anything conversation-shaped, so
  it is deliberately the *last* resort: the tiers decide first, and a prompt is
  consulted only when two windows of the same kind are left and nothing else can
  tell them apart. Any window the terminal has is still taken as a fallback, so
  a lone session is never left without one.

  **A panel cannot be focused past.** `AgentPanel.qml` holds the keyboard
  exclusively while it is up — deliberately, so the keys belong to it — and while
  a layer surface owns the keyboard the compositor will not move the focused
  window at all. `hl.dsp.focus` still warps the cursor to the right window, so
  the symptom is a focus that looks half-done: the mouse arrives, the keyboard
  does not, and `focus = true` does not get past it either. So choosing a row
  closes the card **first** and asks for the focus a beat later, once the surface
  has actually gone. The card does close on the way out rather than on the way
  in, which the code there used to argue the other way about; a card that closes
  *and* leaves the focus where it was is the thing that looks like nothing.
- Turn state: `projects/<basename of the session's cwd>/chats/*/run-state.json`,
  read for one thing, structural:
  - `output.type` — `lastMessage` is the **only** value a completed run leaves
    behind, so it is what a finished turn is read from.

  `error` is **not** read as finished, and not as "still going" either: it is
  what the CLI leaves behind when a run is cut short, which includes every run a
  question interrupts, so an agent that asked you something an hour ago and has
  been working ever since still carries one.
- Step log: `projects/<basename of the session's cwd>/chats/*/log.jsonl`, which
  is where the question signal lives — see below.

### The question signal

`run-state.json` and `chat-messages.json` **cannot** report an open question:
while one is open the CLI writes *nothing at all*, so the tool call and its
answer land in a single write and no unanswered call is ever visible on disk.
Measured, not assumed — a watcher over every file under `~/.config/manicode`
during questions left open for up to two minutes recorded zero writes, and the
`ask-user` block in `chat-messages.json` only ever appears with `answers` already
filled in.

`log.jsonl` can. Every step is bracketed:

```
Start agent <model> step N (<run>)
End   agent <model> step N (<run>)
```

`ask_user` does not return until you answer, so **a step that asked a question is
a bracket that stays open for as long as you take to reply.** An open bracket is
"this step has not finished"; the only question is what counts as too long.
Measured over one long session (225 steps):

| | n | min | p50 | max |
| --- | --- | --- | --- | --- |
| steps that called `ask_user` | 8 | 120.5s | 339s | 1559.9s |
| every other step | 217 | 1.3s | 6s | 38.3s |

A threefold gap with no overlap. `agent-status.sh` derives its bar from that
log rather than hardcoding it — 1.25× the longest non-`ask_user` step recorded
there, floored at 45s — so a machine with slow tools raises its own bar instead
of lighting up on a long build.

**The latency *is* the threshold**: a question is reported one threshold after it
is asked. Measured end-to-end at exactly 60s while the floor was 60s, and now
**50s** (48s threshold plus the bar's 5s poll). Both numbers were pulled as far
as the distribution allows — across 287 ordinary steps the slowest was 38.3s
(p99 25.0s) against a fastest-ever question of 120.5s, so 1.25× on the observed
maximum still leaves 2.5× headroom to the fastest question and 1.25× above the
slowest tool this machine has run.

**A faster signal was looked for and does not exist.** The CLI's per-thread wait
states were sampled throughout an open question: `futex_do_wait` throughout, ids
churning, no thread parked on the tty — identical to a normal run's. Together
with `run-state.json` and `chat-messages.json` (both ruled out above), what is
left is the bracket and how long it has been open.

**The threshold is the one thing here that can be wrong.** It is a measurement,
not a contract: a future tool that legitimately runs for minutes would read as a
question. Two consequences worth knowing: detection lags the question by about
the threshold, so a question answered sooner is never seen at all; and the
bracket is checked *before* `output.type`, precisely so that stale `error` from
an interrupted run cannot paint "needs input" onto a session that is mid-tool-call.

**A cancelled run leaves a bracket that never closes.** The log goes straight
from `Start agent … step N` to `Agent run cancelled by user (abort error)` and
`Main prompt finished` — there is no `End` for the aborted step, because it never
returned. That dead bracket read as a question for the full 80s of the abort,
which is how a false positive was found. `Main prompt finished` is therefore
treated as closing any bracket opened before it, and only one written *after* the
newest `Start` counts — an earlier turn's terminator has nothing to do with the
step in front of us.

Validated by replaying the log: every question detected that lasted longer than
the threshold, 285/285 ordinary steps left alone, the cancelled run left alone,
and the state returns to `working` within seconds of the answer landing. The
`idle` tier is checked against a closed step, a fresh session, and an unreadable
log — the last of which must *not* read idle.

Every session is in one of **four** states, derived in `agent-status.sh` and
carried on each session as `status`:

| status | means | bar badge | panel row |
| --- | --- | --- | --- |
| `waiting` | stopped on a question from you, or on an error | `pal.waiting` (pink-red) | same |
| `finished` | stopped because it is done, with something to read | `pal.finished` (yellow) | same |
| `working` | going, and needs nothing from you | `pal.working` (green) | same |
| `idle` | up, but nothing started and nothing finished | **no dot** | `pal.idle` (gray) |

`error` is lumped into `waiting` rather than given a colour of its own: both want
the same thing from you and nothing from the badge.

**`idle` means "positively nothing", never "we could not tell".** It is reported
only when the log says so — every step that began has ended (`closed`), or none
ever began (`nostart`). A bracket that could not be read at all falls through to
`working`, because claiming idle on an unreadable log would silently strip the
badge off an agent that is very much running. Uncertainty costs a green dot; it
never costs the absence of one.

**The bar and the panel treat `idle` differently, on purpose.** A badge is a
claim that something wants you, so the bar withholds the dot from `idle` and from
no-session-at-all: a dot that carries no meaning is worse than no dot, because it
marks a quiet shell and trains you to ignore it. `idle` and "none" are told apart
on the bar by brightness instead — full for a live session, dimmed to 0.45 for
none. A row in the panel's list is not making that claim; it is answering "what
is every session doing", and an undotted row read as a gap in the list rather
than as a state. So the panel dots `idle` gray, duller than the other three
because it is the only one that means *nothing is happening*.

All four roles are **fixed** in `BarPalette.qml`, not pywal's, for the same
reason `alert` is: each carries a fixed meaning, so a wallpaper must not be able
to repaint one state as the other.

### The lease file is not the session list

`freebuff-live-<pid>.json` is tied to the **remote sponsored slot**, not to the
local process — the CLI deletes it the moment the server session stops being
`active`, while the CLI itself keeps working. A session whose slot has lapsed
therefore has no file, and used to vanish from the reading entirely: the badge
went dark mid-run. `agent-status.sh` now also finds sessions by walking the
process table for a bare `freebuff` whose directory has a conversation under it.
(`freebuff --terminal-command-broker` is the CLI's own tool helper and must be
excluded, or every command run adds a phantom row to the panel.)

The bar for "is a session" is a **conversation directory**, not a
`run-state.json`, and there is **no age check** on it. Both were hiding real
sessions:

- The CLI creates the conversation and its `log.jsonl` on connect; the first
  `run-state.json` only appears after the first step *ends*. A session opened
  and left at its prompt therefore has a conversation and no state file, and
  gating on the state file made it invisible — which is the exact session a
  status panel exists to show. Its log contains no `Start agent` entry, so it
  reads as `nostart` → `idle`, the honest answer.
- A session left open on a question for days writes **nothing at all** for as
  long as the question stands, so a recency gate would drop a `waiting` session
  — the worst possible thing to hide.

A running process is itself the proof of life, and a process that was killed
leaves nothing to find, so an age gate here can only produce false negatives it
has no false positives to offset.

**A session's conversation is the newest one, and its state is read only from
inside that conversation — never from a neighbouring one.** The two halves of
that are one rule, and getting it wrong is not a subtlety. Each session gets its
own conversation directory, so a session that has not finished a step has no
`run-state.json` at all; preferring "the newest conversation that *has* one"
then reaches back into a previous, unrelated conversation and adopts its turn as
the live session's. Measured, not guessed: opening a session in a directory that
had history under it came up red — `waiting` — on an agent that had not been
asked a single question, because the conversation it borrowed had ended in an
`error` hours earlier.

Which conversation is current is decided by the **log's** mtime, not the
directory's. A session appends to its log for its whole life, so the newest log
is the live conversation; a directory's mtime only moves when a file appears in
it, so a long-running session's directory keeps its creation time and a rename
into an older conversation can overtake it.

`idle` is only ever claimed from **positive evidence**: every entry in the log
parsed, and every step that began has ended (`closed`), or none ever began
(`nostart`). A log that parsed to *zero* entries is reported as `unreadable`,
which is a different thing from `nostart` and falls through to `working` — as
does a log that could not be read at all. Uncertainty costs a green dot, never
the absence of one.

Green and pink-red because those are the two things the badge asks you to act on:
"it is going" and "it is your turn". `finished` was a flat gray, which read as
*idle* rather than *done* — and it is the state most worth looking at. That is
also why the same gray is now *right* for `idle` in the panel: the state it read
as by accident is the one it now means. It is deliberately **not** `alert`
(`#a55555`), which is the notification bell's own dot; sharing it would make
"the agent is waiting" and "you have an unread notification" the same mark. The
same values are repeated as fallbacks in `AgentPanel.qml` and
`AgentIndicator.qml` — three each, since the bar never draws `idle`; keep those
strings identical to the palette's.

The bar's badge (`AgentIndicator` → BarItem's `dot`) reports the **most urgent**
state any session is in, in the order **waiting → finished → working**, then
`idle` and none wearing no badge at all.

`finished` outranks `working` deliberately. Both mean the agent is not moving
right now, so the only question is which one has something for you: `finished`
does, `working` does not. Ranking `working` higher put the green "ignore me" dot
on top of a yellow "come and read this" one.

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
