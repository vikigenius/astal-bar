local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local GLib = astal.require("GLib")
local map = require("lua.lib.common").map
local Github = require("lua.lib.github")

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
		Widget.Label({
			label = "Loading GitHub events...",
		}),
	})
end

local function ErrorIndicator()
	return Widget.Box({
		class_name = "error-indicator",
		valign = "CENTER",
		halign = "CENTER",
		vexpand = true,
		Widget.Label({
			label = "Failed to fetch events",
		}),
	})
end

local function EventItem(props, close_window)
	return Widget.Button({
		class_name = "github-event-item",
		on_clicked = function()
			close_window()
			GLib.spawn_command_line_async(string.format("xdg-open %s", props.url))
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

local function GithubFeed(close_window)
	return Widget.Scrollable({
		vscrollbar_policy = "AUTOMATIC",
		hscrollbar_policy = "NEVER",
		class_name = "github-feed",
		setup = function(self)
			local events_var = Variable.new({})

			local function fetch_events()
				local github_events = Github.get_events()
				if not github_events then
					events_var:set({ error = true })
					return
				end

				if #github_events == 0 then
					events_var:set({ empty = true })
					return
				end

				local formatted_events = map(github_events, function(event)
					return {
						type = format_event_type(event.type),
						actor = event.actor.login,
						repo = format_repo_name(event.repo),
						time = Github.format_time(event.created_at),
						avatar_url = event.actor.avatar_url,
						url = string.format("https://github.com/%s", event.repo.name),
					}
				end)

				events_var:set(formatted_events)
			end

			fetch_events()
			local timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Github.POLL_INTERVAL, function()
				fetch_events()
				return true
			end)

			self.child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 8,
				bind(events_var):as(function(evt)
					if evt.error then
						return ErrorIndicator()
					end
					if evt.empty or #evt == 0 then
						return LoadingIndicator()
					end
					return Widget.Box({
						orientation = "VERTICAL",
						spacing = 8,
						map(evt, function(event)
							return EventItem(event, close_window)
						end),
					})
				end),
			})

			self:hook(self, "destroy", function()
				GLib.source_remove(timer)
				events_var:drop()
			end)
		end,
	})
end

local GithubWindow = {}

function GithubWindow.new(gdkmonitor)
	local Anchor = astal.require("Astal").WindowAnchor
	local window
	local is_closing = false

	local function close_window()
		if window and not is_closing then
			is_closing = true
			window:hide()
			is_closing = false
		end
	end

	window = Widget.Window({
		class_name = "GithubWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 10,
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
				}),
			}),
			GithubFeed(close_window),
		}),
	})

	return window
end

return GithubWindow
