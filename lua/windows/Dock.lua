local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Apps = astal.require("AstalApps")
local dock_config = require("lua.lib.dock-config")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")
local Variable = astal.Variable
local Niri = require("lua.lib.niri")

local apps_singleton
local function get_apps_service()
	if not apps_singleton then
		apps_singleton = Apps.Apps.new()
		if apps_singleton then
			apps_singleton:reload()
		else
			Debug.error("Dock", "Failed to initialize Apps service")
		end
	end
	return apps_singleton
end

local function DockIcon(props)
	if not props.icon then
		Debug.warn("Dock", "Creating dock icon without icon for entry: %s", props.desktop_entry or "unknown")
	end

	return Widget.Button({
		class_name = "dock-icon",
		on_clicked = props.on_clicked,
		Widget.Box({
			orientation = "VERTICAL",
			spacing = 2,
			Widget.Icon({
				icon = props.icon or "application-x-executable",
				pixel_size = 48,
			}),
			Widget.Box({
				class_name = "indicator",
				visible = props.is_running or false,
				hexpand = false,
				halign = "CENTER",
				width_request = 3,
				height_request = 3,
			}),
		}),
	})
end

local function DockContainer()
	local apps = get_apps_service()
	if not apps then
		Debug.error("Dock", "Failed to initialize Apps service")
		return Widget.Box({})
	end

	local available_apps = {}
	local pinned_apps = dock_config.pinned_apps
	local update_pending = false
	local container_active = true
	local windows_var, _, windows_cleanup
	local subscription

	local function update_dock_icons(self)
		if not self or not container_active then
			return
		end

		local children = self:get_children()
		if children then
			for _, child in ipairs(children) do
				self:remove(child)
				child:destroy()
			end
		end

		for _, desktop_entry in ipairs(pinned_apps) do
			local app = available_apps[desktop_entry]
			if app then
				self:add(DockIcon({
					icon = app.icon_name,
					is_running = dock_config.is_running(desktop_entry),
					desktop_entry = desktop_entry,
					on_clicked = function()
						if app.launch then
							app:launch()
						end
					end,
				}))
			end
		end

		for entry, app in pairs(available_apps) do
			if dock_config.is_running(entry) and not dock_config.is_pinned(entry) then
				self:add(DockIcon({
					icon = app.icon_name,
					is_running = true,
					desktop_entry = entry,
					on_clicked = function()
						if app.launch then
							app:launch()
						end
					end,
				}))
			end
		end
	end

	local function update_apps_state(self)
		if not self or not container_active then
			return
		end

		dock_config.update_running_apps()
		local app_list = apps:get_list()
		if not app_list then
			return
		end

		available_apps = {}
		for _, app in ipairs(app_list) do
			if app and app.entry then
				available_apps[app.entry] = app
			end
		end

		pinned_apps = dock_config.pinned_apps
		update_dock_icons(self)
	end

	local function schedule_update(self)
		if not self or not container_active or update_pending then
			return
		end

		update_pending = true
		GLib.timeout_add(GLib.PRIORITY_LOW, 100, function()
			if container_active then
				update_apps_state(self)
			end
			update_pending = false
			return GLib.SOURCE_REMOVE
		end)
	end

	return Widget.Box({
		class_name = "dock-container",
		spacing = 8,
		homogeneous = false,
		halign = "CENTER",
		setup = function(self)
			windows_var, _, windows_cleanup = Niri.create_window_variable({
				window_poll_interval = 5000,
			})

			if windows_var then
				subscription = windows_var:subscribe(function(_)
					if container_active then
						schedule_update(self)
					end
				end)
			end

			update_apps_state(self)

			self:hook(self, "destroy", function()
				container_active = false

				if subscription then
					pcall(function()
						subscription:unsubscribe()
					end)
					subscription = nil
				end

				if windows_cleanup then
					pcall(function()
						windows_cleanup()
					end)
					windows_cleanup = nil
				end

				available_apps = {}
				pinned_apps = nil

				collectgarbage("collect")
			end)
		end,
	})
end

local function create_revealer(content)
	if not content then
		Debug.error("Dock", "Attempting to create revealer with nil content")
		return nil
	end

	return Widget.Revealer({
		transition_type = "SLIDE_UP",
		transition_duration = 200,
		reveal_child = true,
		content,
	})
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Dock", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local visible = Variable(true)
	local hide_timeout
	local revealer
	local dock_window
	local detector_window
	local subscription

	local is_cleaned_up = false

	local function cleanup()
		if is_cleaned_up then
			return
		end
		is_cleaned_up = true

		if hide_timeout and tonumber(hide_timeout) > 0 then
			pcall(function()
				GLib.source_remove(hide_timeout)
			end)
			hide_timeout = nil
		end

		if subscription then
			pcall(function()
				subscription:unsubscribe()
			end)
			subscription = nil
		end

		if visible then
			pcall(function()
				visible:drop()
			end)
		end

		if detector_window then
			pcall(function()
				detector_window:destroy()
			end)
			detector_window = nil
		end

		revealer = nil

		collectgarbage("collect")
	end

	local function show_dock()
		if is_cleaned_up then
			return
		end

		if hide_timeout and tonumber(hide_timeout) > 0 then
			pcall(function()
				GLib.source_remove(hide_timeout)
			end)
			hide_timeout = nil
		end

		visible:set(true)
	end

	local function hide_dock()
		if is_cleaned_up or not visible then
			return
		end

		visible:set(false)
	end

	local function schedule_hide(delay)
		if is_cleaned_up then
			return
		end

		if hide_timeout and tonumber(hide_timeout) > 0 then
			pcall(function()
				GLib.source_remove(hide_timeout)
			end)
			hide_timeout = nil
		end

		hide_timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, delay or 500, function()
			hide_dock()
			hide_timeout = nil
			return GLib.SOURCE_REMOVE
		end)
	end

	local dock_container = DockContainer()

	dock_window = Widget.Window({
		class_name = "Dock",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM + Anchor.LEFT + Anchor.RIGHT,
		setup = function(self)
			subscription = visible:subscribe(function(value)
				if revealer then
					revealer.reveal_child = value
				end

				if self and not is_cleaned_up then
					if value then
						self:get_style_context():add_class("revealed")
					else
						self:get_style_context():remove_class("revealed")
					end
				end
			end)

			self:hook(self, "destroy", cleanup)
		end,
		Widget.EventBox({
			on_hover_lost = function()
				schedule_hide(500)
			end,
			on_hover = show_dock,
			Widget.Box({
				class_name = "dock-wrapper",
				halign = "CENTER",
				hexpand = false,
				setup = function(self)
					if dock_container then
						revealer = create_revealer(dock_container)
						if revealer then
							self:add(revealer)
						end
					end
				end,
			}),
		}),
	})

	detector_window = Widget.Window({
		class_name = "DockDetector",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM + Anchor.LEFT + Anchor.RIGHT,
		Widget.EventBox({
			height_request = 1,
			on_hover = show_dock,
		}),
	})

	detector_window:show_all()

	schedule_hide(1500)

	return dock_window
end
