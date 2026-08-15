-- Application bindings

hl.bind("ALT + RETURN", hl.dsp.exec_cmd("uwsm-app -- " .. terminal), { description = "Terminal" })

hl.bind("SUPER + SHIFT + F", hl.dsp.exec_cmd("uwsm-app -- " .. fileManager .. " --new-window"), { description = "File manager" })

hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("uwsm-app -- " .. browser), { description = "Browser" })

hl.bind("SUPER + SHIFT + ALT + B", hl.dsp.exec_cmd("uwsm-app -- " .. browser .. " --private-window"), { description = "Browser (private)" })

hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd(terminal .. " -e nvim"), { description = "Editor" })

hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd("uwsm-app -- obsidian -disable-gpu --enable-wayland-ime"), { description = "Obsidian" })

hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("uwsm-app -- typora --enable-wayland-ime"), { description = "Typora" })

hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("uwsm-app -- slack"), { description = "SLack" })

hl.bind("SUPER + SHIFT + SLASH", hl.dsp.exec_cmd("uwsm-app -- bitwarden"), { description = "Passwords" })

hl.bind("SUPER + W", hl.dsp.exec_cmd("uwsm-app -- tema"), { description = "Tema" })


-- Web App bindings

-- If your web app url contains '#', type it as '##' to prevent hyprland treating it as a comment

hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("chromium --app=https://music.youtube.com/"), { description = "Youtube Music" })

hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd("chromium --app=https://messages.google.com/web/conversations"), { description = "Google Messages" })


-- Close applications

hl.bind("ALT + W", hl.dsp.window.close(), { description = "Close window" })
