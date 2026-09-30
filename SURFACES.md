# SURFACES.md

The pattern every part of `hayami-shell` follows, for when you are adding one.

A "surface" here is a piece of the desktop shell: the bar, the launcher, the
notification centre, the OSD, the tray, and each popout off the bar. They look
like different features, but they are the same six pieces wired together, and
knowing the pattern is most of knowing how to add the next one.

## The six pieces

```
  1. a state singleton     BarState / NotifState / OsdState / TrayState
  2. a CLI                 bin/.local/bin/hayami-<thing>
  3. an IPC target         IpcHandler { target: "bar" }   ← what the CLI speaks to
  4. one or more surfaces  PanelWindow / Variants over Quickshell.screens
  5. theme tokens          modules/Theme.js, NotifTheme.js, OsdTheme.js
  6. a compositor rule     hypr/.config/hypr/apps/<thing>.lua  (layer_rule)
```

Plus the two things that make it *the shell* rather than a floating window: the
module is registered so the user can toggle it (`BarState.clusters`,
`hayami-bar KEYS`, `menus/bar-toggle.toml`), and the tokens are read from `pal`
so it re-tints with the wallpaper (`SKILLS.md`, `THEME.md`).

## How the existing four are wired

| | Bar | Launcher | Notifications | OSD |
| --- | --- | --- | --- | --- |
| state | `BarState.qml` | *(in `Launcher.qml`)* | `NotifState.qml` | `OsdState.qml` |
| state file | `bar.json` | — | — | — |
| IPC target | `bar` | `launcher` | `notifications` | `osd` |
| CLI | `hayami-bar` | `hayami-menu` | `hayami-notify` | `hayami-osd` |
| surfaces | one per monitor | one | popups + centre, per monitor | one per monitor |
| namespace | `quickshell:bar` | `quickshell:launcher` | `quickshell:notifications` | `quickshell:osd` |
| tokens | `modules/Theme.js` | `launcher/Metrics.js` | `NotifTheme.js` + `NotifColors.qml` | `OsdTheme.js` |
| `layer_rule` | `apps/bar.lua` | `apps/launcher.lua` | — | — |

`TrayState.qml` is the smallest complete example: a singleton, one IPC target,
one verb, one surface. Read it before writing anything large.

## The parts that are easy to get wrong

### One state object, not one per monitor

`shell.qml` instantiates the state **once** and hands it to every surface. The
bar is the same bar on every monitor: an edge or a hidden module applies to all
of them at once, and a drag on one monitor is a change to that one setting.

State singletons are `Item { visible: false }`, not `QtObject` — because
`IpcHandler` and the Quickshell object trackers need an item to attach to. The
invisible root is deliberate; do not "fix" it.

### Surfaces are per monitor, state is not

```qml
Variants {
	model: Quickshell.screens
	delegate: Component { Bar { state: barState; tray: trayState } }
}
```

A surface that shows something on every screen at once needs a gate. The bar
already computes one — `onFocusedMonitor`, "is this the bar on the monitor
with the focus" — and the agent panel reuses it via `focused: bar.onFocusedMonitor`
so one shared `BarState.agentPanel` flag opens a card on exactly one screen. Any
new per-monitor surface that can be toggled needs the same gate.

### The IPC target is the whole contract with the outside world

A keybind, a menu entry and a script all go through `hayami <group> …` → the CLI
→ `qs ipc -c hayami-shell call <target> …` → an `IpcHandler`. Nothing outside
`hayami-shell` should know what the state object is called or where its data
lives. That is what makes the shell rebuildable without touching 40 keybinds.

So: **one flag, one place.** If a panel can be opened by a keybind, by a
click on a module and by a menu, all three must reach the *same* `BarState`
property. The agent panel is the worked example —
`SUPER + A` → `hayami agent panel` → `BarState.agentPanel`, the module's
`onClicked` sets the same flag, and `AgentPanel`'s `visible` binds to it. Two
sources of truth is how a panel ends up spawning a second terminal on every
press.

### State files are state, not config

`$XDG_STATE_HOME/hayami-shell/<thing>.json` (`bar.json`, `agent.json`). The
**defaults in QML are the source of truth** for a fresh machine; the file is
written by the first change and is never committed. A surface that is
constructed with sensible defaults needs no state file at all until the user
changes something.

### Every surface needs a compositor rule only if it is a layer surface

`hypr/apps/<thing>.lua` with `hl.layer_rule({ match = { namespace = "…" },
no_anim = true })`. The reason is not tidiness: Hyprland's default `layers`
animation animates a layer between its old and new geometry, so a bar that moves
edges — or an overlay that appears — is briefly drawn as a stretched slab
across the screen. `no_anim` lands it in one frame.

Namespaces are the bare `quickshell:<thing>` set. Keep them exact: the bar's
rule matches `quickshell:bar`, so a namespace shared with the bar drags the
launcher in with it.

## Adding a surface

- [ ] The state singleton, with its QML defaults and (only if it has settings) a
      `FileView` on `$XDG_STATE_HOME/hayami-shell/<thing>.json`.
- [ ] The `IpcHandler { target: "<thing>" }` and the verbs it accepts.
- [ ] The CLI in `bin/.local/bin/hayami-<thing>`: usage to stderr, `set -uo
      pipefail`, forwards to `qs ipc` (see `BASH.md`), and a line in
      `GROUP_LIST` in `hayami` so `hayami <thing>` works.
- [ ] The surface, `Variants` over screens if per-monitor, gated on the focused
      monitor if it can be opened from a key.
- [ ] Tokens in its own `*Theme.js` (geometry and type — **not colour**), with
      shared chrome aliasing the calendar's values. Colours come from `pal`
      (`SKILLS.md`).
- [ ] The instance in `shell.qml`, with a comment saying what is shared and what
      is per-monitor.
- [ ] `hypr/apps/<thing>.lua` if it is a layer surface.
- [ ] A bind and/or a menu entry (`BINDS.md`), and a toggle in `hayami-bar` if it
      is a bar module.
- [ ] Verified per `VERIFY.md` — including that the surface actually maps
      (`hyprctl layers -j | jq -r '.[].levels[][]? | select(.namespace=="quickshell:<thing>")'`).

## Small things worth knowing

- **The bar is not exclusive** (`exclusiveZone 0`), so windows use the strip
  behind it and the rounded corners float over the desktop. A new panel that
  wants to reserve space is a different kind of thing.
- **The launcher and the agent panel are full-screen layer surfaces with a
  transparent hole**, not popups — which is what lets them take the keyboard and
  close on a click outside. A `PopupWindow` is only for things anchored to an
  item, like a tooltip.
- **A `Process` that starts a window and a `Process` that waits for one are
  different things.** `AgentPanel`'s focus runs the dispatch and closes the card
  on exit, so the panel never outlives the command it ran.
