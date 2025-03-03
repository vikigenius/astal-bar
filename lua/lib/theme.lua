local astal = require("astal")
local Variable = require("astal.variable")
local exec = astal.exec

local Theme = {}

function Theme:New()
	local instance = {
		is_dark = Variable(false),
	}
	setmetatable(instance, self)
	self.__index = self

	instance.is_dark:set(self:get_current_theme_mode() == "dark")

	return instance
end

function Theme:get_current_theme_mode()
	local out, err = exec("dconf read /org/gnome/desktop/interface/color-scheme")
	if err then
		return "light"
	end

	return out:match("prefer%-dark") and "dark" or "light"
end

function Theme:toggle_theme()
	local new_state = not self.is_dark:get()
	local scheme = new_state and "prefer-dark" or "prefer-light"

	exec("niri msg action do-screen-transition")
	exec(string.format("dconf write /org/gnome/desktop/interface/color-scheme \"'%s'\"", scheme))

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
