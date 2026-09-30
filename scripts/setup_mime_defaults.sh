#!/bin/bash

# setup_mime_defaults.sh - say which application opens which file type.
#
# Installing a viewer is not the same as being the default one, and on a fresh
# install those are two different things. When two desktop entries both claim a
# MIME type and nothing has claimed it explicitly, the freedesktop tie-break is
# the desktop file's *filename*, so the alphabetically first one wins:
# `chromium.desktop` beats `org.gnome.gThumb.desktop` for every image format
# they share, and a PNG opens in a web browser. gthumb being in pkglist.txt
# does not prevent this -- it is a property of the file names, not of which
# packages are installed. An explicit association is the only thing that
# survives it.
#
# The list of types is read out of gthumb's own desktop entry rather than
# written out here, so it stays whatever that version of gthumb handles: a
# format gthumb learns to open is picked up on the next run with no edit to
# this file.
#
# Safe to run on its own and safe to run twice: it reports what it changed and
# what was already right, and it never fails the install over a type it could
# not set.

set -uo pipefail

GTHUMB_DESKTOP="org.gnome.gThumb.desktop"

echo "=========================================="
echo "        File Type Defaults               "
echo "=========================================="

if ! command -v xdg-mime &> /dev/null; then
    echo "WARNING: xdg-mime not found (install xdg-utils); leaving defaults alone."
    exit 0
fi

# The entry, from wherever the desktop directories are. A user entry shadows the
# system one, so both are searched and the first hit wins, in that order.
entry=""
for dir in "${XDG_DATA_HOME:-$HOME/.local/share}/applications" /usr/local/share/applications /usr/share/applications; do
    if [ -f "$dir/$GTHUMB_DESKTOP" ]; then
        entry="$dir/$GTHUMB_DESKTOP"
        break
    fi
done

if [ -z "$entry" ]; then
    echo "WARNING: $GTHUMB_DESKTOP not found. Is gthumb installed?"
    echo "         Nothing to associate; leaving defaults alone."
    exit 0
fi

echo "Using: $entry"

# Its MimeType line, split on semicolons, keeping only the images. The
# `^image/` filter is what keeps this script from quietly claiming a type
# gthumb happens to also handle but that nobody wants opening in a picture
# viewer -- today it lists nothing but images, and this is here so that stays
# true if that ever changes.
types=$(sed -n 's/^MimeType=//p' "$entry" | tr ';' '\n' | sed 's/[[:space:]]//g' | grep '^image/' | sort -u)

if [ -z "$types" ]; then
    echo "WARNING: $GTHUMB_DESKTOP claims no image types; nothing to do."
    exit 0
fi

echo ""
changed=0
already=0
failed=0

for mime in $types; do
    current=$(xdg-mime query default "$mime" 2>/dev/null)

    if [ "$current" = "$GTHUMB_DESKTOP" ]; then
        already=$((already + 1))
        continue
    fi

    if xdg-mime default "$GTHUMB_DESKTOP" "$mime" 2>/dev/null; then
        printf '  %-16s %s -> %s\n' "$mime" "${current:-<unset>}" "$GTHUMB_DESKTOP"
        changed=$((changed + 1))
    else
        printf '  %-16s FAILED to set\n' "$mime"
        failed=$((failed + 1))
    fi
done

echo ""
echo "Image types now opening in gthumb: $changed set, $already already correct, $failed failed."
echo ""

# Said once, because it is the one association here that could be unwanted:
# SVG is a document format as much as a picture, and it was reaching Firefox.
# If a browser is the better place for it, put it back with:
#   xdg-mime default firefox.desktop image/svg+xml
if xdg-mime query default image/svg+xml 2>/dev/null | grep -q "$GTHUMB_DESKTOP"; then
    echo "Note: image/svg+xml is now gthumb's too (it was Firefox's)."
    echo "      It is a document format as much as a picture -- see the line above"
    echo "      to send it back to the browser if you would rather."
    echo ""
fi

echo "Done."
