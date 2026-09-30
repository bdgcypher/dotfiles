import QtQuick
import Quickshell
import Quickshell.Io

// Theme colours for the bar, read from pywal.
//
// pywal renders ~/.cache/wal/colors-quickshell.json from
// the template in dotfiles/wal/.config/wal/templates/colors-quickshell.json, and
// every module reads its colours from this object, so a wallpaper change
// re-tints the whole bar live (watchChanges does the reload).
//
// The hardcoded values below are only a fallback for the case where pywal has
// not run yet, so the bar still renders instead of showing invisible text.
QtObject {
    id: pal

    property color background: "#171513"
    property color foreground: "#c5c4c4"
    property color accent: "#CEA56A"
    property color muted: "#686766"
    property var colors: []

    // The colour style.css animates the recording and dictation indicators to.
    readonly property color alert: "#a55555"

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.cache/wal/colors-quickshell.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: pal.apply(text())
        onTextChanged: pal.apply(text())
    }

    function apply(raw) {
        if (!raw)
            return

        var data
        try {
            data = JSON.parse(raw)
        } catch (e) {
            return
        }

        if (data.background)
            pal.background = data.background
        if (data.foreground)
            pal.foreground = data.foreground
        if (data.cursor)
            pal.accent = data.cursor
        if (data.color8)
            pal.muted = data.color8

        var list = []
        for (var i = 0; i < 16; i++) {
            var key = "color" + i
            list.push(data[key] ? data[key] : pal.foreground)
        }
        pal.colors = list
    }
}
