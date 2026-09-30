import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

// "Something the bar cannot observe has changed -- re-read it."
//
// Hyprland publishes no event for several things the bar displays, so a plain
// binding goes stale and nothing ever invalidates it. A workspace's tiling layout
// is the clearest case: listening on the Hyprland event socket through a toggle
// produces nothing at all (only the OSD layer open/close), so
// Hyprland.focusedWorkspace.lastIpcObject.tiledLayout keeps reporting the old
// layout. The armed tiling direction is the same kind of state.
//
// poked() therefore fires from four places:
//
//   1. focusing a different workspace. Hyprland DOES emit workspace events, so
//      this immediately covers switching from a scrolling workspace to a dwindle
//      one.
//   2. the focused window changing, for consumers that set trackActiveWindow.
//      tiling-direction predicts the next window's direction from the focused
//      window's aspect ratio, and its armed state is consumed by the next window
//      that opens -- which takes focus -- so this keeps that glyph honest. It is
//      opt-in because it costs a re-probe on every focus change and values that
//      only depend on the workspace do not want that.
//   3. /tmp/hypr-bar.signal changing. The scripts that change the things above
//      (hypr-toggle-layout, hypr-tiling-direction-toggle) write that file, the
//      same way they used to poke the bar with SIGRTMIN+10/11. FileView watches it with
//      inotify, so the poke is immediate and costs nothing while idle -- including
//      when the file does not exist yet, which is the state after a fresh boot.
//   4. a slow poll, as a net for a change made by something that does not poke:
//      a config reload, a hyprctl eval typed by hand, or the focused window being
//      resized across square.
//
// Consumers re-run a short-lived probe process on every poke, which is not free,
// so each one coalesces pokes that arrive while its probe is already running.
QtObject {
    id: root

    signal poked()

    // Set by consumers whose value depends on which window is focused.
    property bool trackActiveWindow: false

    // An int, not the workspace object itself: the object is replaced on more
    // events than an actual workspace change, and poking then would just re-run
    // the probe for nothing.
    readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

    onFocusedWorkspaceIdChanged: root.poked()

    // The address, not the toplevel object, for the same reason as the workspace
    // id above. Only evaluated when a consumer opts in.
    readonly property string activeWindowAddress: root.trackActiveWindow && Hyprland.activeToplevel ? Hyprland.activeToplevel.address : ""

    onActiveWindowAddressChanged: root.poked()

    property FileView signalFile: FileView {
        path: "/tmp/hypr-bar.signal"
        watchChanges: true
        printErrors: false

        onFileChanged: root.poked()
    }

    property Timer poll: Timer {
        interval: 5000
        running: true
        repeat: true

        onTriggered: root.poked()
    }
}
