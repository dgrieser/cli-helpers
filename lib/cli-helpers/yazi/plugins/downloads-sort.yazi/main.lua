--- @since 25.5.31

local function normalize(path)
	if not path or path == "" then
		return nil
	end
	return path:gsub("/+$", "")
end

local function downloads_dirs()
	local dirs = {}
	local downloads = normalize(os.getenv("DOWNLOADS"))
	local home = normalize(os.getenv("HOME"))

	if downloads then
		dirs[downloads] = true
	end
	if home then
		dirs[home .. "/Downloads"] = true
	end

	return dirs
end

local function apply_if_downloads(dirs)
	local cwd = normalize(tostring(cx.active.current.cwd))
	if cwd and dirs[cwd] and not (cx.active.pref.sort_by == "mtime" and cx.active.pref.sort_reverse) then
		ya.emit("sort", { "mtime", reverse = "yes" })
	end
end

local function setup(state)
	state.dirs = downloads_dirs()

	ps.sub("cd", function()
		apply_if_downloads(state.dirs)
	end)
end

return { setup = setup }
