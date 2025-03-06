local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Apps = astal.require("AstalApps")
local dock_config = require("lua.lib.dock-config")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")
local Variable = require("astal.variable")

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

	local apps_state = Variable({
		available_apps = {},
		running_apps = {},
		pinned_apps = dock_config.pinned_apps,
	})

	local container = Widget.Box({
		class_name = "dock-container",
		spacing = 8,
		homogeneous = false,
		halign = "CENTER",
		setup = function(self)
			local function update_apps_state()
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

				apps_state:set({
					available_apps = available_apps,
					running_apps = dock_config.running_apps,
					pinned_apps = dock_config.pinned_apps,
				})
			end

			local function update_dock_icons(state)
				local children = self:get_children()
				if children then
					for _, child in ipairs(children) do
						self:remove(child)
					end
				end

				for _, desktop_entry in ipairs(state.pinned_apps) do
					local app = state.available_apps[desktop_entry]
					if app then
						self:add(DockIcon({
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

				for entry, app in pairs(state.available_apps) do
					if dock_config.is_running(entry) and not dock_config.is_pinned(entry) then
						Debug.debug("Dock", "Adding running app: %s", entry)
						self:add(DockIcon({
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

			apps_state:subscribe(update_dock_icons)

			local update_timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, function()
				update_apps_state()
				return GLib.SOURCE_CONTINUE
			end)

			self.on_destroy = function()
				if update_timeout then
					GLib.source_remove(update_timeout)
				end
				apps_state:drop()
			end

			update_apps_state()
		end,
	})

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
	local dock_state = Variable({
		visible = true,
		hide_timeout = nil,
	})

	local revealer = nil
	local dock_window = nil

	local function show_dock()
		dock_state:set({
			visible = true,
			hide_timeout = dock_state:get().hide_timeout,
		})
	end

	local function hide_dock()
		dock_state:set({
			visible = false,
			hide_timeout = nil,
		})
	end

	dock_state:subscribe(function(state)
		if revealer then
			revealer.reveal_child = state.visible
		end
		if dock_window then
			if state.visible then
				dock_window:get_style_context():add_class("revealed")
			else
				dock_window:get_style_context():remove_class("revealed")
			end
		end
	end)

	dock_window = Widget.Window({
		class_name = "Dock",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM + Anchor.LEFT + Anchor.RIGHT,
		Widget.EventBox({
			on_hover_lost = function()
				Debug.debug("Dock", "Hover lost, scheduling hide")
				local current_state = dock_state:get()
				if current_state.hide_timeout then
					GLib.source_remove(current_state.hide_timeout)
				end
				local timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, function()
					hide_dock()
					return GLib.SOURCE_REMOVE
				end)
				dock_state:set({
					visible = current_state.visible,
					hide_timeout = timeout,
				})
			end,
			on_hover = function()
				local current_state = dock_state:get()
				if current_state.hide_timeout then
					GLib.source_remove(current_state.hide_timeout)
					dock_state:set({
						visible = current_state.visible,
						hide_timeout = nil,
					})
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
			dock_state:drop()
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
