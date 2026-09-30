# SKILLS.md

How to add something to `hayami-shell` so that it looks like it was always
there, and so that it re-tints with the wallpaper like everything else.

This is the *authoring* companion to `AGENTS.md`. `AGENTS.md` says what the
repo is and what never to do; this says how to write a new piece of the shell
so it matches what is already there. Read `AGENTS.md` first — especially
"the one rule that matters" (never edit under `$HOME`, always `stow`) and the
Hyprland Lua-dispatch trap.

## The five extension points

A "plugin" in this shell is one of these. Most work is a bar module plus one
of the rest.

| You want | You are writing | The reference to copy from |
| --- | --- | --- |
| A reading on the bar | a `BarItem` subclass in `modules/` | `CpuIndicator.qml` (scalar) or `AgentIndicator.qml` (everything) |
| Something to read in full | a popout on a layer surface | `VpnPanel.qml` (fixed width) or `AgentPanel.qml` (list + keyboard) |
| Something the user can toggle | a `BarState` flag + a `hayami-bar` verb | `bar.json` → `agentPanel` |
| A command in the menus | a TOML entry in `menus/` | `menus/theme.toml` |
| A new key to press | a Lua binding + a `keybinds.toml` row | `hypr/.config/hypr/bindings/utilities.lua` |

A launcher result that is not an application or a menu entry goes in
`launcher/Providers.js` (see `runnerItems()`) rather than in a bar module.

> **Want something this shell does not have yet?** Do not go looking for a
> module to import. Go to **"Skill: rebuild a plugin natively"** at the end of
> this file: give it a GitHub link, and it works out what the thing does, asks
> you which parts you want, and builds it as a real module of this shell. That
> is the only supported way to add a feature that came from somewhere else.

## Anatomy of a bar module

Every bar module is a `BarItem` — the shared cell in `modules/BarItem.qml` that
already handles the edge, the vertical layout, the hover tooltip, the badge and
the click/scroll signals. A module sets **what** it says; `BarItem` decides
**how** it is said, and every module must fit inside that or the bar stops
looking like one bar.

The three things `Bar.qml` hands every module, and the three that are not
optional:

- `pal:` — the live palette. Never hardcode a colour; read it from here.
- `edge:` — `"top" | "bottom" | "left" | "right"`. The module must read it and
  obey `root.vertical` (a vertical bar stacks glyph-over-value; the horizontal
  one runs them side by side). A module that only works on a top bar is a bug on
  three edges.
- `moduleShown: bar.shownKey("<key>")` — the user's toggle.

Then the module's own contract:

- `glyph` from `Icons.js`, `suffix` for the value. Together they are the
  horizontal label and the two halves of the vertical stack, so a module that
  sets them both gets vertical support for free.
- `marginLeft` / `marginRight`: **6** on both sides for anything in the status
  cluster, so it sits at the same spacing as its neighbours.
- `minWidth` when the reading changes width (a digit appearing), so the bar does
  not shift under the pointer.
- `tooltipText` when hover should say more. It is the shell's tooltip
  (`modules/Tooltip.qml`) with the shell's delay and timeout — there is no second
  tooltip component to reach for.
- `dot` for "something is waiting for you" (`dotColor` defaults to `pal.alert`).
  Reserve the space it needs on the opposite side or the text will jump when it
  appears and disappears.
- `onClicked` / `onRightClicked` / `onScrolled` to do the thing. Prefer spawning a
  terminal with `Quickshell.execDetached([...])` over shelling out from a
  MouseArea.
- A *timer-driven reading* is always: a small script in `scripts/` returning
  one line, run by a `Process` on a 5s `Timer`, parsed with `SplitParser`, with
  `if (!probe.running) probe.running = true` so a slow probe is never overlapped.
  Never a process per frame, and never a blocking call in a binding.

Copy this shape (it is `CpuIndicator.qml` with the comments kept):

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// <thing> -- the one-line reading, and what the click does.
//
// The header is the waybar module this replaces, and what the helper script
// computes. Say why the reading is worth a place on the bar at all.
BarItem {
	id: root

	property int value: 0

	glyph: Icons.<thing>
	suffix: " " + value + "%"

	// The cluster's margin either side, so it slots in at the same spacing.
	marginLeft: 6
	marginRight: 6

	tooltipText: "the sentence, not the number"

	onClicked: Quickshell.execDetached(["ghostty", "-e", "the-thing"])

	Process {
		id: probe
		command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/hayami-shell/scripts/<thing>.sh"]
		stdout: SplitParser { onRead: function(line) { /* parse one line */ } }
	}
	Timer {
		interval: 5000
		running: true
		repeat: true
		onTriggered: { if (!probe.running) probe.running = true }
	}
	Component.onCompleted: probe.running = true
}
```

## Registering a module (there is more than one file)

A new bar key is a change in **four** places. Missing one is the usual way a
"finished" module turns out to be half-plumbed.

1. `modules/<Thing>.qml` — the module.
2. `Bar.qml` — add it to one of the three `BarGroup`s (left / centre / right),
   with `pal`, `edge`, `moduleShown: bar.shownKey("<key>")`, plus any
   `state` / `screenModel` / `focused` it needs.
3. `BarState.qml` — add `"<key>"` to the right `clusters` entry so the launcher
   can switch it as part of a set, and add its open/closed flag if it has a
   popout.
4. `bin/.local/bin/hayami-bar` — add the key to `KEYS` so `hayami-bar toggle
   <key>` and the menu accept it.
5. `menus/bar-toggle.toml` — an entry per module so the launcher offers it.

Then a keybind, if it deserves one:

6. `hypr/.config/hypr/bindings/<topic>.lua` — `hl.bind("SUPER + X",
   hl.dsp.exec_cmd("hayami <thing> <verb>"), { description = "Thing" })`.
7. `quickshell/.../menus/keybinds.toml` — the same row, with the label padded to
   43 columns so the `→` and the key line up.

## Popouts and panels

A popout is a second surface, not a bigger module. Read `VpnPanel.qml` (fixed
width, reading + one action) and `AgentPanel.qml` (list, selection, keyboard)
before writing one.

- It draws the **same chrome as every other flyout**: radius, border width and
  padding alias `Theme.calendarRadius` / `calendarBorderWidth` / `calendarPad` /
  `calendarBarGap` (that is what `vpnPanel*` and `agentPanel*` do). A popout that
  invents its own border is the fastest way to make the shell look patched.
- Only your panel's *own* measurements are new — its width, its row height, its
  font sizes — and each of them goes into `Theme.js` with a comment saying what
  it is for.
- It is a full-screen layer surface with a transparent hole, with a unique
  namespace `quickshell:<thing>`, and `hypr/apps/*.lua` gets a matching rule.
  Open it on **one** monitor: gate the visibility on `focused` (which
  `Bar.qml` already supplies) so one shared flag does not open a card on every
  screen.
- Open/close lives in **one** place — a `BarState` flag, reached by the module
  click, the keybind and the `hayami-bar` verb alike. Never let a module and a
  script keep their own idea of whether the panel is up.
- The one chrome for **focus** in a list: a 2px accent bar down the left edge of
  the row, at text height (`Theme.calendarMarkWidth` / `MarkHeight`). Keyboard
  moves the mark; space/enter or a click does the thing. That is the shell's
  selection language — do not invent a second one.

## Wallpaper theming

The shell's colours come from pywal, once, at the wallpaper:

```
wallpaper ──(apply-wallpaper / pywal)──▶ ~/.cache/wal/colors-quickshell.json
                                                  │
                                          BarPalette.qml  (FileView, watchChanges)
                                                  │
                                    pal: passed down to every module
```

`BarPalette.qml` is the only place a raw colour enters the shell. It maps the
palette to the four roles the shell uses and exposes all 16 as `pal.colors[i]`:

| `pal.*` | pywal key | Used for |
| --- | --- | --- |
| `background` | `background` | surfaces behind text, the dot's inset border |
| `foreground` | `foreground` | the default text/glyph colour |
| `accent` | `cursor` | the shell's accent, the focus colour |
| `muted` | `color8` | secondary/quiet text |
| `colors[i]` | `color0`..`color15` | anything that wants a specific palette slot |
| `alert` | *(hardcoded)* | recording / dictation / "needs you" — deliberately not the wallpaper |

`Bar.qml`'s `accent` is `pal.colors[3]` when the palette has it. **Rules:**

1. **No literal colours in a module, a panel, a script or a menu.** Every colour
   is `pal.<role>`, `pal.colors[i]`, or one of the `Theme` behaviour colours
   (`pulseColor`, the drag-preview alphas). If you catch yourself typing a hex in
   a new file, it belongs in `BarPalette.qml`.
2. **A new semantic role is added to `BarPalette.qml`**, with a sensible fallback
   default next to the existing ones, not sprinkled at the use site. The fallback
   defaults are the only hardcoded colours permitted, and their only job is so
   the shell renders before pywal has ever run.
3. **Tints are derived, not chosen.** Prefer alpha over a palette colour
   (`Qt.alpha`, `Qt.rgba` on `pal.foreground` / `background`) to inventing a
   lighter/darker hex. A palette you did not look at is a palette whose contrast
   you cannot promise, and the shell has to survive every wallpaper.
4. **`alert` stays hardcoded.** It is a fixed alarm colour from the old waybar
   stylesheet, not a wallpaper role. Do not "improve" it to `pal.colors[1]`.
5. **The shell re-tints itself.** `BarPalette` watches the pywal file, so a
   wallpaper change needs **no reload** — do not add one. If a change to a
   non-shell consumer's colours is wanted (a GTK app, ghostty, a TUI), that is a
   pywal *template* in `wal/.config/wal/templates/`, not a shell edit. A colour
   only the shell needs never needs a template.

## Styling rules that are not negotiable

These are what make a new module read as part of the same desktop as the old
ones.

- **Tabs** for indentation, in QML, JS and shell alike. Never spaces.
- **Comments explain *why*, not *what*.** The file's voice is a short "why" block
  at the top naming the thing and the waybar module it came from, then a section
  per concern, then `// ── name ────…` rules at the right width: **77** columns in
  a `.qml`, **68** inside a card/component, **80** in the `.js` theme files.
- **`Theme.js` is geometry and behaviour, not colour.** It was lifted from the
  old waybar stylesheet, and its two hexes (`borderColor`, `pulseColor`) are
  historical references. Do not add a third; do not use it for a new colour.
- **Icon = Nerd Font glyph, added to `Icons.js` as a `\\uXXXX` escape** with a
  `// U+xxxx  nf-md-name` comment, so the file stays ASCII and the codepoint is
  traceable. If a helper script also emits that glyph (as `agent-status.sh` and
  `vpn-status.sh` do), the script writes the same escape — one codepoint, spelled
  once, so the two can never disagree.
- **One chrome.** One accent. One focus mark. One tooltip. A new module that
  re-implements any of those is a patch, not a module.
- **Fit the strip.** A horizontal bar is 26px and a vertical one a 26px well. At
  the vertical value size, a 3-character "100%" nearly fills the well — if the
  reading is wider than that, it belongs on the horizontal line
  (`verticalSide`) or in the popout, not shrunk further.

## Definition of done

Before calling a new piece of the shell finished:

- [ ] Edited in the repo package, then `stow -R -t "$HOME" <package>`.
- [ ] `hayami-shell reload`, and the module is in the log's **load list**.
- [ ] The QML log grep in `AGENTS.md` is clean (a parse failure is silent).
- [ ] It is present on **all four bar edges** (move the bar: `hayami-bar position
      <edge>`), with a sensible vertical layout.
- [ ] The palette comes from `pal`; `grep` the new file for a hex and get none.
- [ ] **Switch the wallpaper and confirm it re-tints with no reload.**
- [ ] The toggle round-trips: `hayami-bar toggle <key>` and the menu entry.
- [ ] Any new measurement lives in `Theme.js` with a "why" comment; shared
      chrome aliases the calendar's values rather than repeating them.
- [ ] A keybind, if added, appears in `keybinds.toml` with the 43-column label.

---

## Skill: rebuild a plugin natively

**Input:** a GitHub link to something you want on this bar — a widget, a panel,
a tool. **Output:** a first-class module of this shell, themed like the rest of
it and registered in all the places a module has to be registered.

There is no plugin system in this shell, and that is deliberate. The previous
arrangement imported a compatibility shim and ran a third-party plugin's QML
inside this process, and it was removed after it produced six separate failures
that all loaded cleanly and did nothing (see "Why not a port" at the end). The
lesson was not "the shim was buggy" — it was that **a faithful copy of somebody
else's layout is not this shell's layout**, and every attempt to reconcile the
two made the result worse.

So: read the upstream to find out what it *does*, then build the thing this
shell would have built.

### 1. Read it, in a scratch checkout, and do not keep it

```sh
git clone --depth 1 https://github.com/OWNER/REPO /tmp/study-thing
```

Read the README for intent, then the source for mechanism. You are looking for
**behaviour**, not appearance:

- What does it observe, and from where? (a script it runs, an HTTP endpoint, a
  D-Bus signal, a file it polls, a socket)
- What does it show, and when does each thing appear?
- What can the user do to it — click, scroll, right-click, type, a key?
- What does it remember between runs, and where?
- What does it need that this machine may not have? (a daemon, a Python
  package, a compositor, a desktop portal)

Write down the answers. If a capability needs something this machine does not
have, that is a fact for step 3, not a reason to stop.

`/tmp` is not the repo. Nothing from `/tmp/study-thing` is ever copied into
`~/.dotfiles` — the implementation is written fresh, against this file's rules.

### 2. Break it into capabilities

One row per thing a person could describe as a feature. Not per file, and not
per component of the original's UI — per *capability*, because the original's
components encode its own layout decisions and those are exactly what you are
throwing away.

| # | Capability | Needs | This shell already has |
| --- | --- | --- | --- |
| 1 | e.g. show current CPU% in the bar | one number every 2s | `CpuIndicator.qml` — read it, it may be 90% of the job |
| 2 | e.g. sparkline of the last 60 samples | a ring buffer | nothing; `modules/` has no chart |
| 3 | e.g. open a panel on click | a `BarState` flag + a surface | `VpnPanel.qml` / `AgentPanel.qml` |

The last column is the important one and it is the whole reason to do this
natively: **most of what a foreign plugin does, this shell already does, in its
own idiom.** Fill it in by grepping `modules/` and reading the nearest
neighbour. A capability whose column is filled in is usually a few lines, or
nothing at all.

### 3. Ask which parts to build

This step is not a formality. Present the table and let the user choose, with
`ask_user`. Offer:

- the capabilities that are cheap because the shell already has them;
- the ones that are genuinely new work;
- and the ones you would *leave out* — the original's settings dialog, its
  multi-monitor layout, its plugin marketplace, anything that is a second
  implementation of something already here.

Also surface, before anyone commits to a capability, the two things that change
the estimate:

- **A dependency the machine does not have** (say so plainly, with what it
  would take to install).
- **A behaviour worth copying that this shell would do differently** — and your
  recommendation.

Do not start writing code in this step. A user who wanted "just the bar reading"
should not end up with a settings dialog.

### 4. Design it as this shell's own module

Before writing, settle these, and say your answers out loud in the work:

- **Where does the data come from, natively?** Almost always a better source
  exists here than in the original: `scripts/*.sh` for system state,
  `Quickshell.Services.*` for media and network, `BarState` for shell state, or
  a 10-line script of your own. Prefer the shell's own source of truth over
  scraping what the original scraped.
- **What shape is it?** One `BarItem` in `modules/`, plus a popout if it needs
  one. Follow "Anatomy of a bar module" above.
- **Which numbers are new?** Every measurement that is not already in `Theme.js`
  goes in with a "why" comment. Shared chrome **aliases** the calendar's values
  (`Theme.calendarRadius`, `calendarPad`, `calendarBorderWidth`,
  `calendarMarkWidth`/`Height`) exactly as `vpnPanel*` and `agentPanel*` do.
- **What does it look like on a vertical bar?** Decide now, not at the end. A
  module that only works on a top bar is a bug on three edges.

### 5. Build it

The rest of this file is the spec. In short, and in the order that avoids
waste:

1. `modules/<Thing>.qml` — a `BarItem` subclass. Tabs, `pal` for every colour,
   `tooltipText` for the hover, no literal hex anywhere.
2. `modules/<Thing>Panel.qml` — only if it needs a popout, copied from
   `VpnPanel.qml` or `AgentPanel.qml`. Same chrome, one `BarState` flag, open
   on the focused monitor only, the shell's 2px accent bar for focus.
3. Any new measurement in `modules/Theme.js`.
4. A script in `scripts/` if it needs one, with its Nerd Font glyph written as
   a `\uXXXX` escape so it matches `Icons.js`.
5. Register it — all of "Registering a module" above: `Bar.qml`, `BarState.qml`,
   `hayami-bar`'s `KEYS`, `menus/bar-toggle.toml`, and optionally a keybind in
   `hypr/.config/hypr/bindings/` plus `menus/keybinds.toml`.
6. `stow -R -t "$HOME" quickshell bin` — never edit under `$HOME`.
7. `hayami-shell reload`, then work through "Definition of done" below.

### 6. Report what you left out

Finish by telling the user which capabilities you did not build and why, in one
paragraph. They chose them from a list; they are owed an accounting of the list.

### Why not a port

Kept because it is the reason this skill exists, and because each of these is a
failure mode a future attempt will otherwise rediscover the hard way. Every one
of them loaded without an error, reported itself healthy, and did nothing.

| What went wrong | The lesson |
| --- | --- |
| The plugin's own spacing scale was re-snapped onto the bar's, so **every one** of its 17 gap calls moved and its proportions were lost | translate intent, never numbers. A gap is a relationship |
| Type sizes were answered by borrowing the VPN panel's, so restyling that panel silently restyled the plugin | a foreign file must not be able to reach this desktop's private tokens |
| An unknown token on an `int` property is **zero**, not an error — so a cell sized itself to 0×0 and drew nothing | in QML, silence is a value. Verify geometry, do not infer it from "it loaded" |
| A `readonly` property bound to a name the shim did not provide stayed `undefined` forever, so the widget could not open its own panel | reimplement the *behaviour*; a missing name has no error to trace |
| A name the original shell injected into plugin scope does not exist here, and it is a `ReferenceError` per call site, at runtime | know what the upstream is assuming about its host |
| A widget authored for a 30px icon slot renders correctly in a 26px bar and reads as a smudge | a faithful copy of someone else's layout is not this shell's layout |

The through-line: **every one of these was invisible from the outside.** A port
that cannot be verified from this side is not a port; it is a hope.
