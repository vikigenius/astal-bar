local astal = require("astal")
local App = require("astal.gtk3.app")
local Debug = require("lua.lib.debug")

local Bar = require("lua.windows.Bar")
local Dock = require("lua.windows.Dock")
local NotificationPopups = require("lua.windows.NotificationPopups")
local OSD = require("lua.windows.OSD")
local src = require("lua.lib.common").src

Debug.set_config({
	log_to_file = true,
	log_to_console = false,
	max_file_size = 1024 * 1024,
	log_level = Debug.LEVELS.DEBUG,
})

Debug.info("App", "Starting astal-bar")

local scss = src("scss/style.scss")
local css = "/tmp/style.css"

astal.exec("sass " .. scss .. " " .. css)

App:start({
	instance_name = "kaneru",
	css = css,
	on_second_instance = function()
		Debug.warn("App", "Another instance attempted to start")
	end,
	request_handler = function(msg, res)
		Debug.debug("App", "Request received: %s", msg)
		res("ok")
	end,
	main = function()
		Debug.info("App", "Initializing main components")
		Bar()
		Dock()
		NotificationPopups()
		OSD()
		-- for _, mon in pairs(App.monitors) do
		--    NotificationPopups(),
		-- end
		Debug.info("App", "All components initialized")
	end,
})
