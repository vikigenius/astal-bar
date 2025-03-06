local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Apps = astal.require("AstalApps")
local dock_config = require("lua.lib.dock-config")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")
local Managers = require("lua.lib.managers")

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
	local apps = Apps.Apps.new()
	if not apps then
		Debug.error("Dock", "Failed to initialize Apps service")
		return nil
	end

	Managers.VariableManager.register(apps)

	local container = Widget.Box({
		class_name = "dock-container",
		spacing = 8,
		homogeneous = false,
		halign = "CENTER",
	})

	local function update_dock()
		local children = container:get_children()
		if children then
			for _, child in ipairs(children) do
				container:remove(child)
			end
		end

		dock_config.update_running_apps()
		local app_list = apps:get_list()
		if not app_list then
			Debug.error("Dock", "Failed to get application list")
			return
		end

		local available_apps = {}

		for _, app in ipairs(app_list) do
			if app and app.entry then
				available_apps[app.entry] = app
			end
		end

		for _, desktop_entry in ipairs(dock_config.pinned_apps) do
			local app = available_apps[desktop_entry]
			if app then
				container:add(DockIcon({
					icon = app.icon_name,
					is_running = dock_config.is_running(desktop_entry),
					desktop_entry = desktop_entry,
					on_clicked = function()
						Debug.info("Dock", "Launching pinned app: %s", desktop_entry)
						if app.launch then
							app:launch()
						else
							Debug.error("Dock", "App %s has no launch method", desktop_entry)
						end
					end,
				}))
			else
				Debug.warn("Dock", "Pinned app not found: %s", desktop_entry)
			end
		end

		for entry, app in pairs(available_apps) do
			if dock_config.is_running(entry) and not dock_config.is_pinned(entry) then
				Debug.debug("Dock", "Adding running app: %s", entry)
				container:add(DockIcon({
					icon = app.icon_name,
					is_running = true,
					desktop_entry = entry,
					on_clicked = function()
						Debug.info("Dock", "Launching running app: %s", entry)
						if app.launch then
							app:launch()
						else
							Debug.error("Dock", "App %s has no launch method", entry)
						end
					end,
				}))
			end
		end
	end

	GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, function()
		update_dock()
		return GLib.SOURCE_CONTINUE
	end)

	update_dock()
	return container
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
	local hide_timeout = nil
	local revealer = nil
	local dock_window = nil

	local function show_dock()
		if revealer then
			revealer.reveal_child = true
		end
		if dock_window then
			dock_window:get_style_context():add_class("revealed")
		end
	end

	local function hide_dock()
		if revealer then
			revealer.reveal_child = false
		end
		if dock_window then
			dock_window:get_style_context():remove_class("revealed")
		end
	end

	dock_window = Widget.Window({
		class_name = "Dock",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM + Anchor.LEFT + Anchor.RIGHT,
		Widget.EventBox({
			on_hover_lost = function()
				Debug.debug("Dock", "Hover lost, scheduling hide")
				if hide_timeout then
					GLib.source_remove(hide_timeout)
				end
				hide_timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, function()
					hide_dock()
					hide_timeout = nil
					return GLib.SOURCE_REMOVE
				end)
			end,
			on_hover = function()
				if hide_timeout then
					GLib.source_remove(hide_timeout)
					hide_timeout = nil
				end
				show_dock()
			end,
			Widget.Box({
				class_name = "dock-wrapper",
				halign = "CENTER",
				hexpand = false,
				setup = function(self)
					revealer = create_revealer(DockContainer())
					if revealer then
						self:add(revealer)
					else
						Debug.error("Dock", "Failed to create dock revealer")
					end
				end,
			}),
		}),
		on_destroy = function()
			Managers.VariableManager.cleanup_all()
		end,
	})

	local detector = Widget.Window({
		class_name = "DockDetector",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM + Anchor.LEFT + Anchor.RIGHT,
		Widget.EventBox({
			height_request = 1,
			on_hover = function()
				show_dock()
			end,
		}),
	})

	detector:show_all()

	GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, function()
		hide_dock()
		return GLib.SOURCE_REMOVE
	end)

	return dock_window
end
