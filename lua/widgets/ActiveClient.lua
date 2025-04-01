local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Variable = astal.Variable
local bind = astal.bind
local utf8 = require("lua-utf8")
local niri = require("lua.lib.niri")

local SANITIZE_PATTERN = "[%z\1-\31\127]"

local function sanitize_utf8(text)
	if not text then
		return ""
	end
	return utf8.gsub(text, SANITIZE_PATTERN, "")
end

local function truncate_text(text, length)
	if not text then
		return ""
	end
	local sanitized = sanitize_utf8(text)
	return utf8.len(sanitized) > length and utf8.sub(sanitized, 1, length) .. "..." or sanitized
end

return function()
	local config = {
		window_poll_interval = 450,
		window_debounce_threshold = 100000,
	}

	local window_var, _, cleanup_fn = niri.create_window_variable(config)

	local app_id_var = Variable.derive({ bind(window_var) }, function(window)
		return sanitize_utf8(window.app_id or "Desktop")
	end)

	local title_var = Variable.derive({ bind(window_var) }, function(window)
		return truncate_text(window.title or "niri", 40)
	end)

	return Widget.Box({
		class_name = "ActiveClient",
		setup = function(self)
			self:hook(self, "destroy", function()
				if cleanup_fn then
					cleanup_fn()
				end
				app_id_var:drop()
				title_var:drop()
			end)
		end,
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
	})
end
