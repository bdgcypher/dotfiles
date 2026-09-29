#!/usr/bin/env python3
"""Flatten the menu TOMLs into JSON for hayami-shell's launcher.

The menu tree is authored as TOML in hayami-shell/menus/*.toml, beside this
script, and is the single source of truth for the launcher's menus; this only
translates the parts the launcher needs (text, icon, default action, weight).

Entries come out sorted by weight, descending, and the TOMLs are already
authored in that order.

The file is written atomically: the launcher watches it, so a half-written file
would make it read a truncated menu tree.

    menus-json.py [output-path] [--quiet]

Prints a one-line JSON summary of what it wrote, which the CLI surfaces.
"""

import glob
import json
import os
import sys
import tomllib

# menus/ sits beside the scripts/ directory this file lives in. realpath so the
# lookup is the same whether this runs from ~/.config (through the stow symlink)
# or straight out of the repository.
BASE_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
MENU_DIR = os.path.join(BASE_DIR, "menus")
DEFAULT_OUT = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "quickshell-hayami-shell-menus.json"
)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv

    out = os.path.expanduser(args[0]) if args else DEFAULT_OUT
    menu_dir = os.path.expanduser(MENU_DIR)

    menus = {}
    skipped = []

    for path in sorted(glob.glob(os.path.join(menu_dir, "*.toml"))):
        try:
            with open(path, "rb") as handle:
                data = tomllib.load(handle)
        except Exception as exc:  # a broken menu must not take the launcher down
            skipped.append({"file": os.path.basename(path), "error": str(exc)})
            continue

        name = data.get("name") or os.path.splitext(os.path.basename(path))[0]

        entries = []
        for entry in data.get("entries", []):
            if not isinstance(entry, dict):
                continue
            entries.append(
                {
                    "text": entry.get("text", ""),
                    "icon": entry.get("icon", ""),
                    "action": (entry.get("actions") or {}).get("default", ""),
                    "weight": entry.get("weight", 0),
                }
            )
        entries.sort(key=lambda item: -item["weight"])

        menus[name] = {
            "name": name,
            "pretty": data.get("name_pretty", name),
            "icon": data.get("icon", ""),
            "entries": entries,
        }

    payload = {"menus": menus, "skipped": skipped}

    try:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False)
        os.replace(tmp, out)
    except OSError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1

    summary = {
        "ok": True,
        "out": out,
        "menus": len(menus),
        "entries": sum(len(menu["entries"]) for menu in menus.values()),
        "skipped": skipped,
    }
    if not quiet:
        print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
