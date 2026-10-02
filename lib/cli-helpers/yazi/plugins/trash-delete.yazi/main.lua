local targets = ya.sync(function()
	local tab, paths = cx.active, {}
	for _, url in pairs(tab.selected) do
		paths[#paths + 1] = tostring(url)
	end
	if #paths == 0 and tab.current.hovered then
		paths[1] = tostring(tab.current.hovered.url)
	end
	return paths
end)

local function entry()
	local paths = targets()
	if #paths == 0 then
		return
	end

	local body = #paths == 1 and ("Move this file to the trash?\n\n" .. paths[1])
		or string.format("Move %d selected files to the trash?", #paths)

	if not ya.confirm({
		pos = { "center", w = 70, h = #paths == 1 and 8 or 6 },
		title = "Trash selected?",
		body = body,
	}) then
		return
	end

	local status, err = Command("trash"):arg("--"):arg(paths):status()
	if not status or not status.success then
		ya.notify({
			title = "trash",
			content = tostring(err or "failed to trash selected file(s)"),
			timeout = 5,
			level = "error",
		})
		return
	end

	ya.emit("escape", { select = true })
end

return { entry = entry }
