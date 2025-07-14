local astal = require("astal")
local astal_gtk3 = require("astal.gtk3")
local Debug = require("lua.lib.debug")
local Widget = require("astal.gtk3.widget")

local Gtk = astal_gtk3.Gtk
local astalify = astal_gtk3.astalify
local Calendar = astalify(Gtk.Calendar)
local CalendarWindow = {}

function CalendarWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("SysInfo", "Failed to initialize: gdkmonitor is nil")
		return nil
	end
	local Anchor = astal.require("Astal").WindowAnchor

	return Widget.Window({
		class_name = "CalendarWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		margin_right = 40,
		child = Calendar({
			setup = function(self)
				self:hook(self, "day-selected", function()
					-- local year, month, day = self:get_date()
					-- print(string.format("Selected date: %04d-%02d-%02d", year, month + 1, day))
				end)
			end,
		}),
	})
end

return CalendarWindow
