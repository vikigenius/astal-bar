local astal = require("astal")
local bind = astal.bind
local Variable = astal.Variable
local Network = astal.require("AstalNetwork")
local Widget = require("astal.gtk3.widget")

local NetworkWidget = {}
local wifi = Network.get_default().wifi
local show_network_list = Variable(false)
local is_enabled = Variable(wifi and wifi.enabled or false)

NetworkWidget.NetworkIcon = function()
  return Widget.Label({
    class_name = "indicator-icon",
    tooltip_text = bind(wifi, "ssid"):as(tostring),
    label = bind(wifi, "icon-name"):as(function(icon_name)
      return icon_name
    end),
  })
end

local remove_duplicates = function(list)
  local seen = {}
  local result = {}
  for _, item in ipairs(list) do
    if item.ssid and not seen[item.ssid] then
      table.insert(result, item)
      seen[item.ssid] = true
    end
  end
  return result
end

local sort_by_priority = function(list)
  table.sort(list, function(a, b)
    return (a.strength or 0) > (b.strength or 0)
  end)
end

local keep_first_n = function(list, n)
  local result = {}
  for i = 1, math.min(n, #list) do
    table.insert(result, list[i])
  end
  return result
end

local connect_to_access_point = function(access_point)
  if not access_point or not access_point.ssid then
    return
  end
  astal.exec_async(string.format("nmcli device wifi connect %s", access_point.bssid))
end

NetworkWidget.NetworkList = function()
  if not wifi or not wifi.enabled then
    return Widget.Box({
      class_name = "expanded-menu",
      orientation = "VERTICAL",
      spacing = 5,
      Widget.Label({
        label = "Turn on Wi-Fi to see available networks",
      }),
    })
  end

  return Widget.Box({
    class_name = "expanded-menu",
    orientation = "VERTICAL",
    spacing = 5,
    bind(wifi, "access_points"):as(function(access_points)
      local list = {}
      for _, ap in ipairs(access_points or {}) do
        if ap and ap.ssid and ap.ssid ~= "" then
          table.insert(list, ap)
        end
      end

      list = remove_duplicates(list)

      sort_by_priority(list)

      list = keep_first_n(list, 5)

      local buttons = {}
      for _, item in ipairs(list) do
        local is_active = wifi.active_access_point and wifi.active_access_point.ssid == item.ssid

        table.insert(buttons, Widget.Button({
          class_name = "network-item" .. (is_active and " active" or ""),
          on_clicked = function()
            connect_to_access_point(item)
          end,
          Widget.Box({
            class_name = "text",
            Widget.Icon({
              icon = item.strength >= 67 and "network-wireless-signal-excellent-symbolic"
                  or item.strength >= 34 and "network-wireless-signal-good-symbolic"
                  or "network-wireless-signal-weak-symbolic",
            }),
            Widget.Label({
              label = item.ssid,
            }),
          }),
        }))
      end
      return buttons
    end),
  })
end

NetworkWidget.ToggleButton = function()
  local expand_button = Widget.Button({
    class_name = "expand-button",
    setup = function(self)
      show_network_list:subscribe(function(expanded)
        self.child.icon = "pan-down-symbolic"
      end)
    end,
    child = Widget.Icon({ icon = "pan-down-symbolic" }),
  })

  expand_button.on_clicked = function()
    show_network_list:set(not show_network_list:get())
  end

  local toggle_button = Widget.Button({
    class_name = "toggle-button with-arrow",
    hexpand = true,
    setup = function(self)
      if is_enabled:get() then
        self:get_style_context():add_class("active")
      end
      is_enabled:subscribe(function(enabled)
        local style_context = self:get_style_context()
        if enabled then
          style_context:add_class("active")
        else
          style_context:remove_class("active")
        end
      end)
    end,
    child = Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Icon({ icon = "network-wireless-symbolic" }),
      Widget.Label({ label = "Wi-Fi" }),
    }),
  })

  toggle_button.on_clicked = function()
    is_enabled:set(not is_enabled:get())
    if is_enabled:get() then
      wifi.enabled = true
      wifi:connect()
    else
      wifi.enabled = false
    end
  end

  return Widget.Box({
    orientation = "HORIZONTAL",
    spacing = 0,
    toggle_button,
    expand_button,
  })
end

return function()
  return Widget.Box({
    class_name = "toggle-container",
    orientation = "VERTICAL",
    spacing = 2,
    NetworkWidget.ToggleButton(),
    Widget.Revealer({
      transition_duration = 200,
      transition_type = "SLIDE_DOWN",
      reveal_child = show_network_list(function(value)
        return value
      end),
      NetworkWidget.NetworkList(),
    }),
  })
end
