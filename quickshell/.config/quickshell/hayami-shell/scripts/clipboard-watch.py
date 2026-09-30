#!/usr/bin/env python3
"""Append each new clipboard entry to the launcher's history.

Run under `wl-paste --watch`, which pipes the new selection to stdin on every
change. The whole file is rewritten atomically each time, because the launcher
watches it: a partial write would show a truncated history.

This is a store of its own rather than a read-back of some other clipboard
owner's history, which was a Go gob blob that could not be read back:

    ${XDG_STATE_HOME:-~/.local/state}/hayami-shell/clipboard.jsonl
    ${XDG_STATE_HOME:-~/.local/state}/hayami-shell/clipboard/    (image bytes)

Entries are one JSON object per line. Text is stored as a bare JSON string,
which is how the file started and needs no migration; anything else is an object:

    {"type": "image", "file": "...", "mime": "image/png",
     "w": 1920, "h": 1080, "bytes": 204800}

Images are written to their own directory named after the hash of their bytes,
so re-copying the same screenshot does not store it twice. Recent entries first,
duplicates moved to the top, capped at 100 entries. Blank
entries are ignored, and image files that fall out of the history are deleted.
"""

import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys

MAX_ITEMS = 100

# A pasted screenshot is a few megabytes; this is a guard against something
# enormous (a raw export, a video frame) filling the state directory.
MAX_IMAGE_BYTES = 64 * 1024 * 1024

# In preference order. image/svg+xml is deliberately absent: an SVG clipboard
# entry is text, and gets stored as text like any other.
IMAGE_MIMES = ("image/png", "image/jpeg", "image/webp", "image/bmp", "image/gif")

# The text flavours wl-copy offers alongside text/plain, kept so a plain-text
# copy is never mistaken for something else. Anything the clipboard labels
# text/* is treated as text as well.
TEXT_MIMES = ("text/plain", "text/plain;charset=utf-8", "TEXT", "STRING", "UTF8_STRING")

EXTENSIONS = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/webp": ".webp",
    "image/bmp": ".bmp",
    "image/gif": ".gif",
}


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return os.path.join(base, "hayami-shell")


def history_path():
    return os.path.join(state_dir(), "clipboard.jsonl")


def image_dir():
    return os.path.join(state_dir(), "clipboard")


def wl_paste(*args, binary=False):
    exe = shutil.which("wl-paste")
    if not exe:
        return None
    try:
        result = subprocess.run(
            [exe, *args],
            capture_output=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout if binary else result.stdout.decode("utf-8", "replace")


def clipboard_types():
    """The MIME types currently offered, in the clipboard's preference order."""
    listed = wl_paste("--list-types")
    if not listed:
        return []
    return [line.strip() for line in listed.splitlines() if line.strip()]


def image_dimensions(data, mime):
    """(width, height) from the header, or (None, None).

    Read directly rather than with an imaging library: this runs on every copy,
    and Pillow is not a dependency of anything else here.
    """
    try:
        if mime == "image/png" and data[:8] == b"\x89PNG\r\n\x1a\n":
            width, height = struct.unpack(">II", data[16:24])
            return width, height

        if mime == "image/gif" and data[:6] in (b"GIF87a", b"GIF89a"):
            width, height = struct.unpack("<HH", data[6:10])
            return width, height

        if mime == "image/bmp" and data[:2] == b"BM":
            width, height = struct.unpack("<ii", data[18:26])
            return abs(width), abs(height)

        if mime == "image/jpeg" and data[:2] == b"\xff\xd8":
            # Walk the segments to the start-of-frame, which holds the size.
            i = 2
            while i + 9 < len(data):
                if data[i] != 0xFF:
                    i += 1
                    continue
                marker = data[i + 1]
                if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                    i += 2
                    continue
                length = struct.unpack(">H", data[i + 2:i + 4])[0]
                if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                    height, width = struct.unpack(">HH", data[i + 5:i + 9])
                    return width, height
                i += 2 + length
    except (struct.error, IndexError, ValueError):
        pass
    return None, None


def decode_text(raw, mime_types):
    """The selection as text, or None when it is not text at all.

    wl-paste --watch pipes the selection to stdin whatever it is: copy an image
    and stdin carries the raw PNG, which is what used to make this script die on
    a UnicodeDecodeError ('utf-8' codec can't decode byte 0x89) and silently drop
    every image. So the bytes are read as bytes, and the clipboard's own type
    list decides how to interpret them.
    """
    if not raw:
        return None

    is_text = any(t in mime_types for t in TEXT_MIMES)
    if not is_text:
        is_text = any(t.startswith("text/") for t in mime_types)
    if not is_text:
        return None

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        # A text type that is not UTF-8 (Latin-1 from an old app, say) should
        # still be kept rather than dropped.
        text = raw.decode("utf-8", "replace")

    text = text.rstrip("\n")
    return text if text.strip() else None


def load(path):
    entries = []
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except ValueError:
                    continue
    except OSError:
        pass
    return entries


def save(path, entries):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            for entry in entries:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
        os.replace(tmp, path)
    except OSError:
        return False
    return True


def same_entry(a, b):
    """Identity for dedupe: text by value, images by the file they live in."""
    if isinstance(a, dict) and isinstance(b, dict):
        return a.get("file") == b.get("file") and a.get("file") is not None
    return a == b


def referenced_files(entries):
    return {e["file"] for e in entries if isinstance(e, dict) and e.get("file")}


def sweep_images(entries):
    """Delete stored images the history no longer refers to.

    This covers the ones trimmed away above and any left behind by an
    interrupted run, so the directory cannot grow without bound.
    """
    keep = referenced_files(entries)
    directory = image_dir()
    try:
        names = os.listdir(directory)
    except OSError:
        return
    for name in names:
        path = os.path.join(directory, name)
        if path in keep:
            continue
        try:
            os.remove(path)
        except OSError:
            pass


def store_image(mime, data):
    try:
        os.makedirs(image_dir(), exist_ok=True)
    except OSError:
        return None

    digest = hashlib.sha256(data).hexdigest()[:32]
    path = os.path.join(image_dir(), digest + EXTENSIONS.get(mime, ".img"))
    if not os.path.exists(path):
        try:
            with open(path, "wb") as handle:
                handle.write(data)
        except OSError:
            return None

    width, height = image_dimensions(data, mime)
    return {
        "type": "image",
        "file": path,
        "mime": mime,
        "w": width,
        "h": height,
        "bytes": len(data),
    }


def main():
    path = history_path()

    # Read the selection as bytes: it is text for a text copy and the raw image
    # for an image copy.
    raw = sys.stdin.buffer.read()
    types = clipboard_types()

    entry = decode_text(raw, types)

    if entry is None:
        # Not text, so it may be an image. The bytes are usually already in
        # `raw`; they are fetched by type only if wl-paste piped nothing.
        for mime in IMAGE_MIMES:
            if mime not in types:
                continue
            data = raw if raw else wl_paste("-t", mime, binary=True)
            if not data:
                continue
            if len(data) > MAX_IMAGE_BYTES:
                return 0
            entry = store_image(mime, data)
            break

    if entry is None:
        return 0

    entries = [e for e in load(path) if not same_entry(e, entry)]
    entries.insert(0, entry)
    entries = entries[:MAX_ITEMS]

    if not save(path, entries):
        return 1

    # Only after the history is written, so a file is never deleted while the
    # history still points at it.
    sweep_images(entries)
    return 0


if __name__ == "__main__":
    sys.exit(main())
