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

    // The three badge colours the agent module wears: `working` while a run is
    // in progress, `finished` while a turn is over and waiting to be read, and
    // `waiting` while the agent is blocked on a question from you (or has
    // errored -- see below). All fixed rather than pywal-derived for the same
    // reason alert is: they carry a fixed meaning, so a wallpaper that happened
    // to put its own hue in the slot must not be able to repaint one state as
    // the other.
    //
    // Green for working, because it is going and needs nothing from you. Yellow
    // for finished: a turn that is over and waiting to be read is *not* urgent,
    // but it is still the one worth looking at, so it wants a colour that reads
    // as *yours* rather than as idle. It has been both of the alternatives:
    // gray said idle, and pink said alarm, which is wrong when nothing is wrong
    // and there is simply a reply to collect. Yellow sits between them and is
    // the only one of the three that means "done, go and look".
    //
    // Pink-red for waiting: the one state that is *blocked on you*. It has to be
    // the loudest of the three, because it is the only one where the agent has
    // stopped and will not start again until you answer. Deliberately not alert
    // (#a55555): that is the notification bell's own dot, and reusing it here
    // would make "the agent is waiting on you" and "you have an unread
    // notification" the same mark. This is pinker and lighter for that reason.
    //
    // All three come from the same family as the shell's other defaults, and
    // each is far enough from the others to be told apart on a 9px dot --
    // 6.8:1, 9.3:1 and 5.2:1 against the bar background.
    //
    // `error` deliberately wears waiting's colour rather than one of its own.
    // An errored turn and a question both want the same thing from you and
    // nothing from the badge: read the agent, then act. One colour for "it has
    // stopped and is waiting on you" is also one less thing to learn at a glance.
    readonly property color working: "#88b667"
    readonly property color finished: "#e5c07b"
    readonly property color waiting: "#e06c9f"

    // `idle` is the fourth agent state, and the only one the *panel* draws: the
    // bar's badge deliberately stays empty for it, because a badge is a claim
    // that something needs you and an agent at its prompt does not. In the
    // panel's row list it does get a dot, gray, so that "up and doing nothing"
    // is visibly a state rather than a gap in the list.
    //
    // Gray, and the dullest of the four by design -- it is the only one that
    // means "nothing is happening", and a colour that asked for attention would
    // be lying. It is fixed for the same reason the other three are.
    //
    // Worth noting against the note on `finished` above: gray was rejected
    // *there* because a gray dot next to a waiting-to-be-read turn read as
    // "idle", which was the wrong message. Here it is the literal truth, and the
    // two are told apart by their neighbours in the same row -- the same grey
    // that was ambiguous as "finished" is exact as "idle".
    readonly property color idle: "#7a7a7a"

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
