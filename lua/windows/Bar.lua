local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Variable = astal.Variable
local GLib = astal.require("GLib")
local bind = astal.bind
local Mpris = astal.require("AstalMpris")
local Tray = astal.require("AstalTray")

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

-- local function AudioSlider()
-- 	local speaker = Wp.get_default().audio.default_speaker

-- 	return Widget.Box({
-- 		class_name = "AudioSlider",
-- 		css = "min-width: 140px;",
-- 		Widget.Icon({
-- 			icon = bind(speaker, "volume-icon"),
-- 		}),
-- 		Widget.Slider({
-- 			hexpand = true,
-- 			on_dragged = function(self)
-- 				speaker.volume = self.value
-- 			end,
-- 			value = bind(speaker, "volume"),
-- 		}),
-- 	})
-- end

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
      }),
    }),
  })
end
