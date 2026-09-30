# LAUNCHER.md

How the launcher is put together, and how to add a provider to it.

The launcher is the replacement for walker + elephant. It is 3,700 lines across
six files, and the split is deliberate:

| File | Owns |
| --- | --- |
| `Query.js` | which providers a mode queries, the prefix triggers, the fuzzy ranking |
| `Providers.js` | the **item builders** — one function per provider, turning raw data into scored items |
| `Fuzzy.js` | fzf's `FuzzyMatchV2`, ported (the scoring primitive) |
| `Metrics.js` | the box's geometry and type, all in one file so tuning is one place |
| `Box.qml` | the drawn box: rows, selection, hover |
| `Launcher.qml` | the window, the keyboard, the data sources, and **what activating an item does** |

The line that matters: **a provider cannot activate anything.** `Providers.js` is
a plain `.pragma library` with no Quickshell import, so it can only describe an
item. The behaviour lives in `Launcher.qml`'s `activate()`, which switches on
`item.kind`. That is why a new provider is two edits, not one.

## The item contract

Every builder returns the same shape:

```js
{
	text: "Agent Panel",          // the row's label
	fields: ["Agent Panel", …],   // the ordered list the query is matched against
	minScore: 30,                 // elephant's MinScore: the threshold it must clear
	subtext: "SUPER + A",         // the right-hand grey text
	icon: "",                     // a Nerd Font glyph, or ""
	weight: 0,                    // static ordering, before any scoring
	kind: "menu",                 // ← decides what activating it does
	…anything else the kind needs  // path, value, url, isDir, mime, action, app
}
```

- `fields` **in order**: the best-scoring field wins, and each field costs 5
  points of score (at most 50), so a match in the name beats the same match in
  the subtitle. That is why the name is field 0.
- `minScore` is the real tuning knob — it decides how much a query pulls in.
  The existing values are chosen, not defaults: **50** for `runner` (typing part
  of a command name should give you *that command*, not everything echoing it),
  **0** for `symbols` (the list is the flat view of a dataset you are already
  searching by hand), **30** for applications, **10** for menus.
- `kind` must be one the `activate()` switch knows, or the item is inert.

## The kinds that exist, and what each does

| `kind` | Activating it |
| --- | --- |
| `app` | runs the desktop entry's command through `bash -lc`, after hiding the launcher |
| `menu` | runs the entry's action (a `hayami-menu -m …` string) |
| `runner` | `Quickshell.execDetached([item.path])` — the command itself |
| `symbol`, `clipboard` | copy the value and paste it into the window that had focus |
| `clipboard-image` | same, by mime, from the file the watcher saved |
| `calc` | copies the result |
| `websearch` | `xdg-open` on the built URL |
| `file` | a directory re-roots the query into it; a file opens it |
| `provider` | switches the launcher into that provider's mode |
| `dmenu` | a dmenu-mode selection, reported on stdout and exiting |

Two rules that come out of that switch: **hide the launcher before spawning
anything**, and never build a shell command by concatenation without quoting —
`shellQuote()` in `Launcher.qml` is the quoting helper, and `calc` is the
example of using it.

## Adding a provider

1. **The data.** If it changes slowly, bake it: add a generator to
   `scripts/providers-json.py` (it writes
   `$XDG_RUNTIME_DIR/quickshell-hayami-shell-providers.json` once per session —
   "scripts" already works this way, scanning `PATH`). If it is live, source it
   in `Launcher.qml` the way the clipboard watcher or the Hyprland IPC is
   sourced. **Never shell out per keystroke.**
2. **The builder** in `Providers.js` — one function, returning the shape above,
   with a comment saying what the source is and why the `minScore` is what it
   is.
3. **The wiring** in `Launcher.qml`: a case in the `providers` switch that
   returns `Providers.<yourBuilder>(raw)`.
4. **The behaviour**: a new `kind` needs a branch in `activate()`. Reusing an
   existing kind (`runner`, `websearch`, `file`) is nearly always the right
   answer and needs no new branch.
5. **The mode**: `Query.js` — add the id to `DEFAULT_SET` if it should be
   searchable from the main view, add a `PLACEHOLDERS` entry so the box has a
   title, and add a `PREFIXES` entry if it gets a trigger character.
6. **Discoverability**: `BUILTIN_PROVIDERS` is the list behind `/`. Add an entry
   there only if the provider actually answers — unimplemented elephant
   providers were deliberately left out of it, because listing one produces
   empty results and looks broken.

## Modes and triggers

`providerSetFor()` decides the set in four steps, in this order:

1. `-m <provider>` (a keybind or menu opened a specific mode) → just that one.
2. The query's first character is a trigger → just that provider.
3. The query is empty → `SET_EMPTY`, which is `menus:main` alone. This is why
   the launcher opens as five top-level entries instead of one long list.
4. Otherwise → `DEFAULT_SET`, everything searchable.

The triggers are `/` (provider list), `.` (files), `:` (emoji), `=` (calc),
`@` (web search), `$` (clipboard).

A new **menu** is a provider too: `menus:<path>` is built from the baked TOML
cache, and its title comes from `PLACEHOLDERS` — so a menu added to
`menus/*.toml` without a placeholder there opens with its raw id as the
heading. `BINDS.md` covers that side.

## Emoji is the exception

Emoji is **not** in `providers-json.py` any more, and should not be put back.
It used to come from Python's own Unicode database, which has names but no
shortcodes, no categories and no skin tones — and the grid needs all of those.
The launcher reads the vendored `data/emoji/emojis.json` (built by
`scripts/build-emoji-data.py`) instead, so the list and the grid are the same
data and can never disagree on a name. The shortcodes go into `fields` as
keywords, which is what makes `:+1`, `:thumbsup` and `thumbs up` all find the
same entry.

## Checking a provider

- `Query.rank()` is a pure function over items and a query, so a scoring change
  can be reasoned about without the window — read the comment block in `Query.js`
  for the exact algorithm (it applies elephant's position penalty *twice*, and
  the MinScores are tuned against that).
- In the running shell, the load-list check and `hayami-shell logs` apply as
  usual (`VERIFY.md`). A `console.log` inside the builder shows what it returned
  for the current query.
- For a keyboard walkthrough, `wtype` drives the box (`VERIFY.md`); remember to
  restore the focused window afterwards with the Lua `hl.dsp.focus` form.
- `hayami-menu --dmenu` makes the launcher a picker for scripts (it reads stdin
  and returns the choice) — that is a *mode*, not a headless test; it still
  opens a window.

## Do not

- Do not put behaviour in `Providers.js`. It has no Quickshell import precisely
  so that it cannot.
- Do not shell out on every keystroke. Bake the static lists, watch the live
  ones.
- Do not add a provider to `BUILTIN_PROVIDERS` that returns nothing.
- Do not tune `minScore` by feel alone — it is the difference between "type two
  letters, get your command" and "type two letters, get everything".
- Do not hand-tune geometry in `Box.qml`; it belongs in `Metrics.js`.
