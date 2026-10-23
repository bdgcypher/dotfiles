--- @since 26.9.1
--
-- `<Enter>` does two jobs here, because yazi has no way to add a key for one
-- launch only: a yazi opened as the agent's directory picker needs Enter to
-- *choose* the highlighted directory and quit, while an ordinary yazi needs the
-- `open` Enter has always emitted. So keymap.toml prepends `<Enter>` for this
-- plugin and this decides at run time -- `HAYAMI_AGENT_PICK` set means "picking",
-- anything else falls straight through to the stock behaviour.
--
-- That fallback is load-bearing: this is the same yazi the desktop's own file
-- chooser runs (xdg-desktop-portal-termfilechooser), and Enter in it has to keep
-- opening things.
--
-- The file it writes is the whole answer to `hayami agent new`, and it is
-- deliberately not yazi's own `--cwd-file`: that one is written when yazi is
-- killed as well, so closing the picker window would read as a choice. Only this
-- runs on Enter and nowhere else, which is what makes "no file" mean "cancelled".

local M = {}

-- `cx` is readable only from the main thread, so the hovered entry and the cwd
-- are read inside ya.sync and handed back as one plain path.
--
-- Directory-ness is read off `hovered.cha.is_dir`, a plain field. `fs.cha()`
-- would be the obvious call and cannot be used: it is async, and a ya.sync body
-- is not a coroutine, so it fails with "attempt to yield from outside a
-- coroutine" -- after opening the answer file, which then reads as an empty
-- answer.
local choose = ya.sync(function()
	local current = cx.active.current
	local hovered = current.hovered

	if hovered and hovered.cha and hovered.cha.is_dir then
		return tostring(hovered.url)
	end

	-- A file under the cursor is not a working directory; the directory being
	-- looked at is, and that is what someone pointing at its contents means.
	return tostring(current.cwd.path or current.cwd)
end)

function M:entry(job)
	local out = os.getenv("HAYAMI_AGENT_PICK")
	if not out or out == "" then
		ya.emit("open", {})
		return
	end

	local file = io.open(out, "w")
	if file then
		file:write(choose())
		file:close()
	end
	ya.emit("quit", {})
end

return M
