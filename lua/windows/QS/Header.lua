local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Battery = astal.require("AstalBattery")
local bind = astal.bind
local exec = astal.exec

local function getBatteryTimeString(bat)
  -- You might want to implement this based on the actual Battery API
  local timeToEmpty = bat.time_to_empty or 0
  if timeToEmpty == 0 then
    return "Fully charged"
  end

  local hours = math.floor(timeToEmpty / 3600)
  local minutes = math.floor((timeToEmpty % 3600) / 60)

  if hours > 0 then
    return string.format("%d hours %d minutes remaining", hours, minutes)
  else
    return string.format("%d minutes remaining", minutes)
  end
end

local function Header()
  local bat = Battery.get_default()

  return Widget.Box({
    class_name = "QuickSettingsHeader",
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Box({
        orientation = "VERTICAL",
        halign = "START",
        Widget.Label({
          label = bind(bat, "percentage"):as(function(p)
            return string.format("%.0f%%", p * 100)
          end),
          class_name = "battery-label",
          xalign = 0,
        }),
        Widget.Label({
          label = bind(bat, "time_to_empty"):as(function()
            return getBatteryTimeString(bat)
          end),
          class_name = "battery-time",
          xalign = 0,
        }),
      }),
      Widget.Box({
        orientation = "HORIZONTAL",
        halign = "END",
        hexpand = true,
        spacing = 5,
        Widget.Button({
          child = Widget.Icon({ icon = "camera-photo-symbolic" }),
          on_clicked = function()
            exec("niri msg action screenshot")
          end,
        }),
        Widget.Button({
          child = Widget.Icon({ icon = "preferences-system-symbolic" }),
        }),
        Widget.Button({
          child = Widget.Icon({ icon = "system-lock-screen-symbolic" }),
        }),
        Widget.Button({
          child = Widget.Icon({ icon = "system-shutdown-symbolic" }),
        }),
      }),
    }),
  })
end

return Header
