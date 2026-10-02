--- @sync entry
--- Smart <Esc>: cancel whatever is active (visual mode, selection, filter,
--- find, search); quit only when there is nothing left to cancel.

local function active()
	local tab = cx.active
	if tab.mode.is_select or tab.mode.is_unset then
		return true -- visual mode
	elseif #tab.selected > 0 then
		return true -- files selected
	elseif tab.finder then
		return true -- find in progress
	elseif tab.current.files.filter then
		return true -- filter applied
	elseif tab.current.cwd.is_search then
		return true -- search results
	end
	return false
end

return {
	entry = function()
		ya.emit(active() and "escape" or "quit", {})
	end,
}
