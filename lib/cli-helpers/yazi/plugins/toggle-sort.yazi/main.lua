--- @since 25.5.31
--- @sync entry

local function entry()
	local pref = cx.active.pref
	if pref.sort_by == "mtime" and pref.sort_reverse then
		ya.emit("sort", { "natural", reverse = "no" })
	else
		ya.emit("sort", { "mtime", reverse = "yes" })
	end
end

return { entry = entry }
