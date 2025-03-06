local astal = require("astal")
local Variable = require("astal.variable")
local exec = astal.exec
local Debug = require("lua.lib.debug")

local Theme = {}

function Theme:New()
	local instance = {
		is_dark = Variable(false),
	}
	setmetatable(instance, self)
	self.__index = self

	local current_theme = self:get_current_theme_mode()
	if not current_theme then
		Debug.error("Theme", "Failed to get initial theme state")
		current_theme = "light"
	end
	instance.is_dark:set(current_theme == "dark")

	return instance
end

function Theme:get_current_theme_mode()
	local out, err = exec("dconf read /org/gnome/desktop/interface/color-scheme")
	if err then
		Debug.error("Theme", "Failed to read dconf theme setting: %s", err)
		return nil
	end

	return out:match("prefer%-dark") and "dark" or "light"
end

function Theme:toggle_theme()
	local new_state = not self.is_dark:get()
	local scheme = new_state and "prefer-dark" or "prefer-light"

	local _, err = exec("niri msg action do-screen-transition")
	if err then
		Debug.error("Theme", "Failed to trigger screen transition: %s", err)
	end

	local _, err_dconf = exec(string.format("dconf write /org/gnome/desktop/interface/color-scheme \"'%s'\"", scheme))
	if err_dconf then
		Debug.error("Theme", "Failed to set theme: %s", err_dconf)
		return
	end

	self.is_dark:set(new_state)
end

local instance = nil
function Theme.get_default()
	if not instance then
		instance = Theme:New()
	end
	return instance
end

return Theme
