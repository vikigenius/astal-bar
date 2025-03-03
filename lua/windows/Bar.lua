local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Variable = astal.Variable
local bind = astal.bind
local GLib = astal.require("GLib")
local Mpris = astal.require("AstalMpris")
local Tray = astal.require("AstalTray")
local Battery = astal.require("AstalBattery")

local QuickSettings = require("lua.widgets.QuickSettings")
local Vitals = require("lua.widgets.Vitals")
local ActiveClient = require("lua.widgets.ActiveClient")

local map = require("lua.lib.common").map

local function SysTray()
  local tray = Tray.get_default()

  return Widget.Box({
    class_name = "SysTray",
    bind(tray, "items"):as(function(items)
      return map(items, function(item)
        return Widget.MenuButton({
          tooltip_markup = bind(item, "tooltip_markup"),
          use_popover = false,
          menu_model = bind(item, "menu-model"),
          action_group = bind(item, "action-group"):as(function(ag)
            return { "dbusmenu", ag }
          end),
          Widget.Icon({
            gicon = bind(item, "gicon"),
          }),
        })
      end)
    end),
  })
end

local function Media()
  local player = Mpris.Player.new("spotify")

  return Widget.Box({
    class_name = "Media",
    visible = bind(player, "available"),
    Widget.Box({
      class_name = "Cover",
      valign = "CENTER",
      css = bind(player, "cover-art"):as(function(cover)
        return "background-image: url('" .. (cover or "") .. "');"
      end),
    }),
    Widget.Label({
      label = bind(player, "metadata"):as(function()
        return (player.title or "") .. " - " .. (player.artist or "")
      end),
    }),
  })
end

local function Time(format)
  local time = Variable(""):poll(1000, function()
    return GLib.DateTime.new_now_local():format(format)
  end)

  return Widget.Label({
    class_name = "Time",
    on_destroy = function()
      time:drop()
    end,
    label = time(),
  })
end

local function BatteryLevel()
  local bat = Battery.get_default()
  local window_visible = false
  local battery_window = nil

  local function toggle_battery_window()
    if window_visible and battery_window then
      battery_window:hide()
      window_visible = false
    else
      if not battery_window then
        local BatteryWindow = require("lua.windows.Battery")
        battery_window = BatteryWindow.new() -- Use the .new() constructor
      end
      battery_window:show_all()
      window_visible = true
    end
  end

  return Widget.Button({
    class_name = "battery-button",
    visible = bind(bat, "is-present"),
    on_clicked = toggle_battery_window,
    Widget.Box({
      Widget.Icon({
        icon = bind(bat, "battery-icon-name"),
        css = "padding-right: 5pt;",
      }),
      Widget.Label({
        label = bind(bat, "percentage"):as(function(p)
          return tostring(math.floor(p * 100)) .. " %"
        end),
      }),
    }),
  })
end

return function(gdkmonitor)
  local Anchor = astal.require("Astal").WindowAnchor

  return Widget.Window({
    class_name = "Bar",
    gdkmonitor = gdkmonitor,
    anchor = Anchor.TOP + Anchor.LEFT + Anchor.RIGHT,
    exclusivity = "EXCLUSIVE",
    Widget.CenterBox({
      Widget.Box({
        halign = "START",
        ActiveClient(),
      }),
      Widget.Box({
        Time("%B %d, %H:%M"),
        Media(),
      }),
      Widget.Box({
        halign = "END",
        Vitals(),
        SysTray(),
        QuickSettings(),
        BatteryLevel(),
      }),
    }),
  })
end
