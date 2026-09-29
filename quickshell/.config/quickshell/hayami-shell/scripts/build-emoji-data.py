#!/usr/bin/env python3
"""Build the emoji picker's dataset from emojibase-data.

The output is vendored (data/emoji/emojis.json), so this script is not part of
the install flow -- it is here so the file can be regenerated or audited rather
than being an opaque blob. Run it when the upstream data moves to a new Unicode
version:

    scripts/build-emoji-data.py [output-path]

Source: emojibase-data (https://github.com/emojibase/emojibase-data), MIT.
Three files are consumed from the published npm package:

    en/data.json                 every emoji, with group, CLDR order, tags and
                                 the skin-tone variants of each
    en/messages.json             group labels and the skin-tone ordering
    en/shortcodes/emojibase.json `:shortcodes:` keyed by hexcode

What gets kept, and why the shape is this compact: the file is parsed into the
launcher's memory on every shell start, so the keys are shortened and the parts
that can be derived are dropped. A skin variant's label is "<label>: <tone> skin
tone" and its hexcode is "<hex>-<modifier>", so only the character is stored.

    {
      "source": "emojibase-data@<version> (MIT)",
      "groups": [ { "key", "label", "order" } ],   # index is `g` below
      "tones":  [ "light", ... ],                  # index is `k` below
      "emoji":  [ {
          "c": "😀",              # the character, emoji presentation
          "l": "grinning face",   # label, used for display and search
          "h": "1F600",           # hexcode, for a stable identity
          "g": 0,                 # index into "groups"
          "o": 1,                 # CLDR order within the group
          "s": ["grinning"],      # shortcodes, without the colons
          "t": ["face", "grin"],  # search tags
          "k": ["😀🏻", ...]        # one entry per tone, null when not supported
      } ]
    }

Components (standalone skin-tone and hair modifiers) and regional indicators
(the half-flag letters) are dropped: they are building blocks, not emoji you
would pick from a grid.
"""

import json
import os
import sys
import urllib.request

VERSION = "16"
BASE = "https://cdn.jsdelivr.net/npm/emojibase-data@" + VERSION

# emojibase group numbers to drop. 2 is Component, which holds the skin-tone and
# hair modifiers on their own.
SKIP_GROUPS = {2}

# The tone order emojibase numbers its `tone` field by, which is the Unicode
# order (1F3FB..1F3FF). messages.skinTones is listed alphabetically, so it
# cannot be used for the index -- taking it as-is maps tone 1 (light) to dark.
TONE_ORDER = ["light", "medium-light", "medium", "medium-dark", "dark"]

# Text-presentation characters need VS16 to render as emoji; emojibase leaves
# them in "text" and empties "emoji" for those.
VS16 = "\ufe0f"


def fetch(name):
    url = BASE + "/" + name
    with urllib.request.urlopen(url, timeout=90) as response:
        return json.loads(response.read().decode("utf-8"))


def titlecase(text):
    """emojibase labels are lowercase; the box shows them title case."""
    return " ".join(word.capitalize() for word in text.split())


def character(entry):
    """The char to draw, preferring emoji presentation."""
    if entry.get("emoji"):
        return entry["emoji"]
    text = entry.get("text") or ""
    if not text:
        return ""
    # A text-presentation char (e.g. the heart, the watch) is not drawn in
    # colour without the variation selector.
    return text + VS16


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.abspath(os.path.expanduser(args[0])) if args else os.path.join(
        here, "..", "data", "emoji", "emojis.json"
    )

    data = fetch("en/data.json")
    messages = fetch("en/messages.json")
    shortcodes = fetch("en/shortcodes/emojibase.json")

    # messages.groups is already in CLDR order; its index becomes `g`.
    groups = []
    group_index = {}
    for group in sorted(messages["groups"], key=lambda g: g["order"]):
        if group["order"] in SKIP_GROUPS:
            continue
        group_index[group["order"]] = len(groups)
        groups.append({
            "key": group["key"],
            "label": titlecase(group["message"]),
            "order": group["order"],
        })

    tone_labels = {t["key"]: titlecase(t["message"]).replace(" Skin Tone", "")
                   for t in messages["skinTones"]}
    tones = [tone_labels[key] for key in TONE_ORDER]

    # Shortcodes are keyed by uppercase hexcode.
    codes_by_hex = {}
    for hexcode, names in shortcodes.items():
        codes_by_hex[hexcode.upper()] = names if isinstance(names, list) else [names]

    emoji = []
    skipped_component = 0
    skipped_nochar = 0
    for entry in data:
        group = entry.get("group")
        if group in SKIP_GROUPS:
            skipped_component += 1
            continue
        if group is None or group not in group_index:
            # Regional indicators and anything ungrouped: half a flag, not an
            # emoji you would pick.
            continue

        char = character(entry)
        if not char:
            skipped_nochar += 1
            continue

        hexcode = entry["hexcode"].upper()
        skins = entry.get("skins") or []
        # Indexed by tone (1..5) so the picker can apply a tone by position.
        tone_chars = [None] * len(tones)
        for skin in skins:
            tone = skin.get("tone")
            if isinstance(tone, int) and 1 <= tone <= len(tones):
                tone_chars[tone - 1] = character(skin)

        emoji.append({
            "c": char,
            "l": entry.get("label") or "",
            "h": hexcode,
            "g": group_index[group],
            "o": entry.get("order") or 0,
            "s": codes_by_hex.get(hexcode, []),
            "t": entry.get("tags") or [],
            "k": tone_chars if any(tone_chars) else None,
        })

    # CLDR order, which is what upstream recommends for a palette.
    emoji.sort(key=lambda e: (e["g"], e["o"]))

    payload = {
        "source": "emojibase-data@" + VERSION + " (MIT, https://github.com/emojibase/emojibase-data)",
        "groups": groups,
        "tones": tones,
        "emoji": emoji,
    }

    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        # Separators matter: this file is read into memory on every shell start.
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, out)

    print(json.dumps({
        "ok": True,
        "out": out,
        "bytes": os.path.getsize(out),
        "groups": [g["key"] for g in groups],
        "tones": tones,
        "emoji": len(emoji),
        "with_tones": sum(1 for e in emoji if e["k"]),
        "with_shortcodes": sum(1 for e in emoji if e["s"]),
        "skipped_components": skipped_component,
        "skipped_nochar": skipped_nochar,
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
