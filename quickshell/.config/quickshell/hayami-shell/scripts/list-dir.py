#!/usr/bin/env python3
"""Directory listing for the launcher's files provider (the "." prefix).

The argument is the path typed after the prefix, which may be partial:

    ""                    -> the home directory
    "~/Documents"         -> that directory
    "~/Documents/re"      -> that directory, entries starting with "re"
    "/etc/hosts"          -> /etc, entries starting with "hosts"

Directories come first, then files, each alphabetically, and the list is capped
so a huge directory cannot blow up the launcher's model.

    list-dir.py [path]
"""

import json
import os
import sys

MAX_ENTRIES = 300


def main(argv):
    raw = argv[1] if len(argv) > 1 else ""
    expanded = os.path.expanduser(raw) if raw else os.path.expanduser("~")

    if os.path.isdir(expanded):
        base, prefix = expanded, ""
    else:
        # A partial name: list its parent and filter, so typing narrows the
        # directory you are already in.
        base = os.path.dirname(expanded) or os.path.expanduser("~")
        prefix = os.path.basename(expanded)

    try:
        names = os.listdir(base)
    except OSError as exc:
        print(json.dumps({"ok": False, "error": str(exc), "dir": base}))
        return 0

    low = prefix.lower()
    directories = []
    files = []
    for name in names:
        if low and not name.lower().startswith(low):
            continue
        full = os.path.join(base, name)
        entry = {"name": name, "dir": os.path.isdir(full), "path": full}
        (directories if entry["dir"] else files).append(entry)

    directories.sort(key=lambda item: item["name"].lower())
    files.sort(key=lambda item: item["name"].lower())
    entries = (directories + files)[:MAX_ENTRIES]

    print(json.dumps({"ok": True, "dir": base, "prefix": prefix, "entries": entries}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
