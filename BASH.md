# BASH.md

How scripts are written here, and the traps in this shell that have already
cost time.

The shell has two kinds of script, and they are written slightly differently:

- **Commands** — `bin/.local/bin/*`, the things a keybind or a menu calls. Most
  are one-liners wrapping a bigger tool (`ts-up`, `pi`, `rb`); the `hayami-*`
  family is the real work.
- **Probes** — `hayami-shell/scripts/*`, the small programs the bar runs every
  few seconds to produce one line of text.

## The house rules

- **`bash` with `set -uo pipefail`.** Not `-e`: a command in this repo often
  expects a failure (`grep` finding nothing, a window that has already gone).
  With `-e` those become silent exits at the worst possible moment.
  The `hayami-*` family and `agent-status.sh` set it; several of the older
  one-liners (`theme-mode`, `toggle-theme-mode`, `screen-record`) predate the
  convention. **New code sets it.**
- **Usage and errors go to stderr**, so a command's stdout stays pipeable.
  Every script has a `usage()` that writes with `cat >&2 <<EOF` or
  `printf … >&2`, and an unknown argument prints the error *and* the usage to
  stderr, then exits non-zero.
- **Tabs**, everywhere, in shell as in QML.
- **Comments say why.** The convention in this repo is a header block naming the
  script, its invocation forms, and the non-obvious decision; then `#
  ── name ─────…` section rules.
- **Machine-readable output on stdout, one line, no decoration.** A probe that
  feeds a `SplitParser` in QML must print exactly what the parser expects and
  nothing else. Everything else goes to stderr.
- **State in `$XDG_RUNTIME_DIR`, not `/tmp`.** A runtime file must not survive a
  reboot, and `cpu.sh` says why: a stale sample there would be diffed against
  nothing and read as 0%.
- **A command never reimplements a verb that already exists.** `hayami` is a
  dispatcher with no logic of its own on purpose — a `bar toggle` copy inside it
  would drift from `hayami-bar`.

## Traps in this shell

Each of these was hit while working in this repo, and each fails *quietly*.

### `${var/#$HOME/~}` is a no-op here

The `#` pattern form does not expand `$HOME` in the pattern, so a "shortened
path" silently stays absolute — and nothing complains, because the output is
still a valid path. Use `case`:

```bash
shorten() {
	case "$1" in
		"$HOME") printf '~' ;;
		"$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
		*) printf '%s' "$1" ;;
	esac
}
```

### An apostrophe inside a single-quoted `jq` program

`jq -r '.[] | select(.x | test("bar's"))'` — the `'` in `bar's` **closes the
shell string**. The shell then waits for more input, or reports a syntax error
several tokens later at an unrelated `|`. Use a `case` statement instead of
`test("bar's")`, or escape: `"bar'"'"'s"`.

### `GROUPS` is a special variable

`GROUP_LIST=(…)` is fine. `GROUPS=(…)` is **silently ignored** — bash's special
array of the user's numeric group IDs wins, and the list you wrote is simply
gone. That is why `hayami` names its array `GROUP_LIST`, with a comment.
The same applies to `UID`, `EUID`, `PPID`, `RANDOM`, `SECONDS`, `LINENO`,
`PIPESTATUS`, `REPLY`, `OPTARG`.

### `pkill -f` matches the wrong process

`pkill -f -- "-c hayami-shell"` matches any shell, editor or terminal whose
command line merely *mentions* those words — including the one running the
command. `hayami-shell` therefore matches on the **argv array** via
`/proc/<pid>/cmdline`, checking `argv[0]` is actually `qs` and that `-c` is
followed by the id. Copy that function rather than reaching for `pkill -f`.

### `local x=$(cmd)` swallows the exit status

In bash, `local` resets `$?`, so a failure inside the assignment is invisible
to the very next line. Split them:

```bash
local out
out=$(cmd) || return 1
```

### A dispatch that exits 0 and does nothing

`hyprctl dispatch` in this Hyprland is Lua, so the string form is a syntax
error (exit 7) and a non-matching selector is a warning with exit 0. Neither
is distinguishable by status. Use the Lua form and check the text — see
`BINDS.md` and `AGENTS.md`.

### `IFS`, `read -r`, and parsing

`read` without `-r` eats backslashes; `read a b` splits on `IFS`. For a probe
reading `/proc/stat`, both matter:

```bash
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
```

and when a value may itself be empty, split explicitly
(`line.trim().split(/\s+/)` in QML, `set -- $line` in bash) rather than trusting
positional parameters to be what you expect.

### Scratch files

`tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT` — set the trap immediately after
creating it, or an early exit leaves the directory behind.

## Writing a new command

- [ ] `#!/usr/bin/env bash`, `set -uo pipefail`, tabs.
- [ ] Header comment: what it is, the invocation forms, and the one non-obvious
      decision.
- [ ] `usage()` to stderr; unknown args print error + usage to stderr, exit ≠ 0.
- [ ] Resolve paths with `$(dirname "$(realpath "$0")")` so the script works
      both from `~/.config` (through the stow symlink) and straight out of the
      repo — this is what `menus-json.py` does, and the reason it has a
      `BASE_DIR` at all.
- [ ] If it drives the shell, use the `hayami <group>` form or the documented
      `qs ipc` target — never a private assumption about the shell's internals.
- [ ] `bash -n` it, and run it with a bad argument to see the usage.
- [ ] Register it if it should be reachable: a bind (`BINDS.md`) or a menu
      entry.

## When to write Python instead

Reach for Python when the task is parsing, not plumbing: TOML (`menus-json.py`
uses `tomllib`), JSON, or anything where a shell one-liner would need three
nested `sed`s. Keep the same house rules — a docstring saying what it reads and
what it writes, output to stdout, diagnostics to stderr. Parse-check without
importing, so no `__pycache__` lands in the tree:

```bash
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" script.py
```
