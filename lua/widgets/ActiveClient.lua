local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Variable = astal.Variable
local bind = astal.bind
local cjson = require("cjson")
local utf8 = require("lua-utf8")
local Debug = require("lua.lib.debug")

local function sanitize_utf8(text)
	return text and utf8.gsub(text, "[%z\1-\31\127]", "") or ""
end

local function truncate_text(text, length)
	if not text then
		return ""
	end
	text = sanitize_utf8(text)
	return utf8.len(text) > length and utf8.sub(text, 1, length) .. "..." or text
end

local function get_active_window()
	local out, err = astal.exec("niri msg --json windows")
	if err then
		Debug.error("ActiveClient", "Failed to get window data: %s", err)
		return nil
	end

	local success, windows = pcall(cjson.decode, out)
	if not success then
		Debug.error("ActiveClient", "Failed to decode window data")
		return nil
	end

	for _, window in ipairs(windows) do
		if window.is_focused then
			return window
		end
	end
	return nil
end

local function create_window_variable()
	local var = Variable({})
	return var:poll(400, function()
		return get_active_window() or {}
	end)
end

return function()
	local window_var = create_window_variable()

	local app_id_var = Variable.derive({ bind(window_var) }, function(window)
		return sanitize_utf8(window.app_id or "Desktop")
	end)

	local title_var = Variable.derive({ bind(window_var) }, function(window)
		return truncate_text(window.title or "niri", 40)
	end)

	return Widget.Box({
		class_name = "ActiveClient",
		Widget.Box({
			orientation = "VERTICAL",
			Widget.Label({
				class_name = "app-id",
				label = bind(app_id_var),
				halign = "START",
			}),
			Widget.Label({
				class_name = "window-title",
				label = bind(title_var),
				halign = "START",
				ellipsize = "END",
			}),
		}),
		on_destroy = function()
			window_var:drop()
			app_id_var:drop()
			title_var:drop()
		end,
	})
end
