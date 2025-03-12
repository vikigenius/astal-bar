local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local GLib = astal.require("GLib")
local map = require("lua.lib.common").map
local Github = require("lua.lib.github")
local Debug = require("lua.lib.debug")

local function format_event_type(type)
	return type:gsub("Event", ""):lower()
end

local function format_repo_name(repo)
	return repo.name or ""
end

local function AvatarImage(url)
	return Widget.Box({
		class_name = "avatar-image",
		css = string.format(
			[[
            background-image: url('%s');
            background-size: cover;
            border-radius: 8px;
        ]],
			url
		),
		width_request = 40,
		height_request = 40,
	})
end

local function LoadingIndicator()
	return Widget.Box({
		class_name = "loading-indicator",
		valign = "CENTER",
		halign = "CENTER",
		vexpand = true,
		Widget.Label({ label = "Loading GitHub events..." }),
	})
end

local function ErrorIndicator()
	return Widget.Box({
		class_name = "error-indicator",
		valign = "CENTER",
		halign = "CENTER",
		vexpand = true,
		Widget.Label({ label = "Failed to fetch events" }),
	})
end

local function EventItem(props, close_window)
	return Widget.Button({
		class_name = "github-event-item",
		on_clicked = function()
			close_window()
			GLib.spawn_command_line_async("xdg-open " .. props.url)
		end,
		child = Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 10,
			AvatarImage(props.avatar_url),
			Widget.Box({
				orientation = "VERTICAL",
				spacing = 4,
				hexpand = true,
				Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 5,
					Widget.Label({
						class_name = "actor-name",
						label = props.actor,
						xalign = 0,
					}),
					Widget.Label({
						class_name = "event-type",
						label = props.type,
						xalign = 0,
					}),
					Widget.Label({
						class_name = "repo-name",
						label = props.repo,
						xalign = 0,
						hexpand = true,
					}),
				}),
				Widget.Label({
					class_name = "event-time",
					label = props.time,
					xalign = 0,
				}),
			}),
		}),
	})
end

local function create_events_handler()
	local events_var = Variable.new({ loading = true })
	local last_update_var = Variable.new("")
	local is_loading_var = Variable.new(true)
	local update_label_visible = Variable.new(false)
	local update_timer_id = nil

	local function process_events(github_events)
		if not github_events then
			Debug.warn("GitHub", "Failed to process events: empty data")
			return { error = true }
		end
		if #github_events == 0 then
			Debug.debug("GitHub", "No events received from API")
			return { empty = true }
		end
		return map(github_events, function(event)
			return {
				type = format_event_type(event.type),
				actor = event.actor.login,
				repo = format_repo_name(event.repo),
				time = Github.format_time(event.created_at),
				avatar_url = event.actor.avatar_url,
				url = "https://github.com/" .. event.repo.name,
			}
		end)
	end

	local function start_update_timer()
		if update_timer_id then
			GLib.source_remove(update_timer_id)
		end

		update_timer_id = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 60, function()
			local timestamp = Github.get_last_update_time()
			if timestamp and timestamp > 0 and update_label_visible:get() then
				last_update_var:set(Github.format_last_update(timestamp))
			end
			return true
		end)
	end

	local function load_events()
		GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, function()
			local events, timestamp = Github.get_events()
			events_var:set(process_events(events))

			if timestamp and timestamp > 0 then
				last_update_var:set(Github.format_last_update(timestamp))
			else
				last_update_var:set("Updated just now")
			end

			update_label_visible:set(true)
			is_loading_var:set(false)
			start_update_timer()
			return false
		end)
	end

	local function update_events()
		is_loading_var:set(true)
		events_var:set({ loading = true })
		last_update_var:set("Updating...")

		GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, function()
			local events, timestamp = Github.update_events()
			events_var:set(process_events(events))
			last_update_var:set(Github.format_last_update(timestamp))
			is_loading_var:set(false)
			return false
		end)
	end

	local function cleanup()
		if update_timer_id then
			GLib.source_remove(update_timer_id)
			update_timer_id = nil
		end
	end

	return events_var, last_update_var, is_loading_var, update_label_visible, load_events, update_events, cleanup
end

local GithubWindow = {}

function GithubWindow.new(gdkmonitor)
	local Anchor = astal.require("Astal").WindowAnchor
	local window
	local is_closing = false
	local update_events_func
	local first_map = true

	local function close_window()
		if window and not is_closing then
			is_closing = true
			window:hide()
			is_closing = false
		end
	end

	local events_var, last_update_var, is_loading_var, update_label_visible, load_events, update_events, cleanup_timer =
		create_events_handler()
	update_events_func = update_events

	load_events()

	local content = Widget.Box({
		orientation = "VERTICAL",
		spacing = 8,
		Widget.Box({
			class_name = "header",
			orientation = "HORIZONTAL",
			spacing = 10,
			Widget.Icon({
				icon = os.getenv("PWD") .. "/icons/github-symbolic.svg",
			}),
			Widget.Label({
				label = "GitHub Activity",
				xalign = 0,
				hexpand = true,
			}),
		}),
		Widget.Box({
			class_name = "update-bar",
			orientation = "HORIZONTAL",
			spacing = 8,
			visible = bind(update_label_visible),
			Widget.Label({
				label = bind(last_update_var),
				xalign = 0,
				hexpand = true,
			}),
			Widget.Button({
				class_name = "refresh-button",
				child = Widget.Icon({
					icon = "view-refresh-symbolic",
				}),
				on_clicked = function()
					if not is_loading_var:get() then
						Debug.debug("GitHub", "Refresh button clicked")
						update_events()
					else
						Debug.debug("GitHub", "Refresh button clicked but loading is in progress")
					end
				end,
			}),
		}),
		Widget.Box({
			vexpand = true,
			hexpand = true,
			class_name = "github-feed-container",
			child = bind(events_var):as(function(evt)
				if evt.error then
					return ErrorIndicator()
				end
				if evt.empty or #evt == 0 or evt.loading then
					return LoadingIndicator()
				end
				return Widget.Scrollable({
					vscrollbar_policy = "AUTOMATIC",
					hscrollbar_policy = "NEVER",
					class_name = "github-feed",
					child = Widget.Box({
						orientation = "VERTICAL",
						spacing = 8,
						map(evt, function(event)
							return EventItem(event, close_window)
						end),
					}),
				})
			end),
		}),
		setup = function(self)
			if Github and type(Github.mark_viewed) == "function" then
				Github.mark_viewed()
			end

			self:hook(self, "destroy", function()
				events_var:drop()
				last_update_var:drop()
				is_loading_var:drop()
				update_label_visible:drop()
				if cleanup_timer then
					cleanup_timer()
				end
			end)
		end,
	})

	window = Widget.Window({
		class_name = "GithubWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		width_request = 420,
		height_request = 400,
		child = content,
		setup = function(self)
			self:hook(self, "map", function()
				if first_map then
					first_map = false
					if Github and type(Github.mark_viewed) == "function" then
						Github.mark_viewed()
					end

					local needs_update = false
					if Github and type(Github.get_last_update_time) == "function" then
						local last_update = Github.get_last_update_time()
						local current_time = os.time()
						needs_update = (last_update == 0 or (current_time - last_update > 1800))
					end

					if needs_update then
						GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, function()
							if not is_closing and update_events_func then
								update_events_func()
							end
							return false
						end)
					end
				end
			end)
		end,
	})

	return window
end

return GithubWindow
