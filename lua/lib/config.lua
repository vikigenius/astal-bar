local M = {}

function M.load_user_config()
	local paths = {
		(os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/kaneru/user-variables.lua",
		"/etc/kaneru/user-variables.lua",
		debug.getinfo(1).source:match("@?(.*/)") .. "../../../user-variables.lua",
	}

	for _, path in ipairs(paths) do
		local file = io.open(path, "r")
		if file then
			file:close()
			local success, result = pcall(dofile, path)
			if success and result then
				return result
			end
		end
	end

	return {}
end

return M
