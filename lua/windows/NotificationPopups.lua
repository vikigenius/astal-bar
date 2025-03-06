local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Debug = require("lua.lib.debug")
local Notifd = astal.require("AstalNotifd")
local Notification = require("lua.widgets.Notification")
local timeout = astal.timeout

local notif_service = require("lua.lib.common")

local TIMEOUT_DELAY = 5000

local notifd = Notifd.get_default()
if not notifd then
	Debug.error("NotificationPopups", "Failed to get notification daemon")
end

local function NotificationMap()
	local notif_map = notif_service.varmap({})

	notifd.on_notified = function(_, id)
		local notification = notifd:get_notification(id)
		if not notification then
			Debug.error("NotificationPopups", "Failed to get notification with id: %d", id)
			return
		end

		notif_map.set(
			id,
			Notification({
				notification = notification,
				on_hover_lost = function()
					notif_map.delete(id)
				end,
				setup = function()
					timeout(TIMEOUT_DELAY, function()
						notif_map.delete(id)
					end)
				end,
			})
		)
	end

	notifd.on_resolved = function(_, id)
		notif_map.delete(id)
	end

	return notif_map
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("NotificationPopups", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local notifs = NotificationMap()

	return Widget.Window({
		class_name = "NotificationPopups",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		Widget.Box({
			vertical = true,
			notifs(),
		}),
	})
end
