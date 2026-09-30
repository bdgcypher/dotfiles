#!/usr/bin/env python3
"""Static provider lists for the launcher: Scripts (runner).

These change slowly, so they are generated once per session into the runtime dir
and read from there, rather than shelling out every time the launcher opens.

  * runner -- every executable on PATH, deduped by name, first hit wins. This
              is what the menu offers as "Scripts".

Emoji are not generated here any more. They used to come from Python's own
Unicode database, which has names but no shortcodes, categories or skin tones;
the picker needs all of those, so the launcher reads the vendored dataset
(data/emoji/emojis.json, built by build-emoji-data.py) instead. Both the emoji
grid and the list's ":" provider read that one file, so the two agree on names.

    providers-json.py [output-path] [--quiet]
"""

import json
import os
import sys

DEFAULT_OUT = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "quickshell-hayami-shell-providers.json"
)


def runner():
    seen = {}
    for directory in os.environ.get("PATH", "").split(":"):
        if not directory:
            continue
        try:
            names = os.listdir(directory)
        except OSError:
            continue
        for name in names:
            if name in seen:
                continue
            path = os.path.join(directory, name)
            try:
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    seen[name] = path
            except OSError:
                continue
    return [{"text": name, "path": seen[name]} for name in sorted(seen)]


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv
    out = os.path.expanduser(args[0]) if args else DEFAULT_OUT

    payload = {"runner": runner()}

    try:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False)
        os.replace(tmp, out)
    except OSError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1

    if not quiet:
        print(json.dumps({"ok": True, "out": out, "runner": len(payload["runner"])}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
