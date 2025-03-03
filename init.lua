local astal = require("astal")
local App = require("astal.gtk3.app")

local Bar = require("lua.windows.Bar")
local NotificationPopups = require("lua.windows.NotificationPopups")
local OSD = require("lua.windows.OSD")
local src = require("lua.lib.common").src

local scss = src("scss/style.scss")
local css = "/tmp/style.css"

astal.exec("sass " .. scss .. " " .. css)

App:start({
	instance_name = "kaneru",
	css = css,
	request_handler = function(msg, res)
		print(msg)
		res("ok")
	end,
	main = function()
		Bar()
		NotificationPopups()
		OSD()
		for _, mon in pairs(App.monitors) do
			-- NotificationPopups(),
		end
	end,
})
