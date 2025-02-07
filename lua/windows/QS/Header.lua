local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Battery = astal.require("AstalBattery")
local bind = astal.bind
local exec = astal.exec

local function getBatteryTimeString(bat)
  local handle = io.popen("upower -i $(upower -e | grep BAT) | grep 'time to'")
  if not handle then return "Unable to get battery info" end

  local result = handle:read("*a")
  handle:close()

  if result then
    result = result:match("^%s*(.-)%s*$")

    local time = result:match("time to [%w]+:%s+(.+)")

    if time then
      return time
    end
  end

  return "Fully Charged"
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
          child = Widget.Icon({ icon = "screenshot-recorded-symbolic" }),
          on_clicked = function()
            exec("niri msg action screenshot")
          end,
        }),
        Widget.Button({
          child = Widget.Icon({ icon = "preferences-system-symbolic" }),
          on_clicked = function()
            exec("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center")
          end,
        }),
        Widget.Button({
          child = Widget.Icon({ icon = "system-lock-screen-symbolic" }),
          on_clicked = function()
            exec("hyprlock")
          end,
        }),
        Widget.Button({
          child = Widget.Icon({ icon = "system-shutdown-symbolic" }),
        }),
      }),
    }),
  })
end

return Header
