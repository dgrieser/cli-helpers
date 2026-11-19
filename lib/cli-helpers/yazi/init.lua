function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	if time == 0 then
		time = ""
	elseif os.date("%Y", time) == os.date("%Y") then
		time = os.date("%b %d %H:%M", time)
	else
		time = os.date("%b %d  %Y", time)
	end

	local size = self._file:size()
	local size_str = size and ya.readable_size(size) or ""
	return string.format("%5s %12s", size_str, time)
end

require("copy-file-contents"):setup {
	append_char = "\n",
	notification = true,
}

require("downloads-sort"):setup()

th.git = th.git or {}
th.git.unknown_sign = "  "
th.git.modified_sign = "✎ "
th.git.ignored_sign = "* "
th.git.untracked_sign = "? "
th.git.deleted_sign = "✘ "
th.git.updated_sign = "☑ "
th.git.clean_sign = "  "
th.git.added_sign = "✔ "

th.git.unknown = ui.Style():fg("darkgray")
th.git.ignored = ui.Style():fg("darkgray")
th.git.untracked = ui.Style():fg("red"):bold()
th.git.modified = ui.Style():fg("lightyellow"):bold()
th.git.added = ui.Style():fg("green"):bold()
th.git.deleted = ui.Style():fg("red"):bold()
th.git.updated = ui.Style():fg("yellow")
th.git.clean = ui.Style():fg("darkgray")

require("git"):setup {
	-- Order of status signs showing in the linemode
	order = 900,
}

-- Keybinding hints in the header, right side (before the selection counter).
-- Hidden on narrow terminals so it never squeezes the cwd.
local HINTS = "v/V visual  y copy  x cut  p/P paste  d trash  z fzf  F1 help"
local HINTS_MIN_WIDTH = 110

Header:children_add(function(self)
	if self._area.w < HINTS_MIN_WIDTH then
		return ""
	end
	return ui.Line { ui.Span(HINTS):fg("darkgray"), "  " }
end, 500, Header.RIGHT)
