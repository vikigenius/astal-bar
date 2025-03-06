local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Debug = require("lua.lib.debug")
local Notifd = astal.require("AstalNotifd")
local Notification = require("lua.widgets.Notification")
local timeout = astal.timeout
local Variable = astal.Variable
local bind = astal.bind

local TIMEOUT_DELAY = 5000

local notifd = Notifd.get_default()
if not notifd then
	Debug.error("NotificationPopups", "Failed to get notification daemon")
end

local function NotificationMap(parent)
	local notifications = Variable({})
	local notif_map = {}

	local function update_notifications()
		local arr = {}
		for _, widget in pairs(notif_map) do
			table.insert(arr, widget)
		end
		notifications:set(arr)
	end

	local function remove_notification(id)
		if notif_map[id] then
			if notif_map[id].destroy then
				notif_map[id]:destroy()
			end
			notif_map[id] = nil
			update_notifications()
		end
	end

	parent:hook(notifd, "notified", function(_, id)
		local notification = notifd:get_notification(id)
		if not notification then
			Debug.error("NotificationPopups", "Failed to get notification with id: %d", id)
			return
		end

		local timer_var = Variable(0)

		notif_map[id] = Notification({
			notification = notification,
			on_hover_lost = function()
				remove_notification(id)
			end,
			setup = function()
				timer_var:subscribe(function()
					remove_notification(id)
				end)

				timeout(TIMEOUT_DELAY, function()
					timer_var:set(1)
				end)
			end,
		})

		update_notifications()
	end)

	parent:hook(notifd, "resolved", function(_, id)
		remove_notification(id)
	end)

	return notifications
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("NotificationPopups", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor

	return Widget.Window({
		class_name = "NotificationPopups",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		setup = function(self)
			local notifs = NotificationMap(self)
			self:add(Widget.Box({
				vertical = true,
				bind(notifs),
			}))
		end,
	})
end
