-- Immediate boot autostarts
-- Run once at session start (equivalent to exec-once); do NOT re-run on reload.
hl.on("hyprland.start", function()
    -- Restore the last set wallpaper and theme
    hl.exec_cmd("restore-wallpaper")
    hl.exec_cmd("wal -R")

    -- Initialize hyprsunset and hyprlock immediately after boot
    hl.exec_cmd("uwsm-app -- hyprsunset")
    hl.exec_cmd("hyprlock")

    -- Slow app launch fix -- set systemd vars (must run before uwsm-app calls)
    hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")

    -- All other autostarts
    hl.exec_cmd("systemctl --user start elephant.service")
    hl.exec_cmd("walker --gapplication-service")
    hl.exec_cmd("uwsm-app -- hypridle")
    -- hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
    hl.exec_cmd("uwsm-app -- sunshine")
    hl.exec_cmd("uwsm-app -- swaync")
    hl.exec_cmd("uwsm-app -- swayosd-server")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Set GTK theme
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark-compact'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")

    -- Set cursor theme (authoritative at runtime; the XCURSOR*/HYPRCURSOR*
    -- env vars from uwsm/env only apply on a fresh session, and hyprctl
    -- setcursor fixes it even when those never reach Hyprland)
    hl.exec_cmd("hyprctl setcursor BreezeX-Black 30")

    -- Mouseless
    hl.exec_cmd("flatpak run net.sonuscape.mouseless")

    -- KDE Connect
    hl.exec_cmd("/usr/lib/kdeconnectd")
    hl.exec_cmd("/usr/bin/kdeconnect-indicator")
end)
