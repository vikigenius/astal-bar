local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Theme = require("lua.lib.theme")
local bind = astal.bind
local exec = astal.exec

local CONSERVATION_MODE_PATH = "/sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/VPC2004:00/conservation_mode"

local function getConservationMode()
  local content, err = astal.read_file(CONSERVATION_MODE_PATH)
  if err then
    return false
  end
  return tonumber(content) == 1
end

local function toggleConservationMode()
  local current = getConservationMode()
  local value = current and "0" or "1"
  local err = astal.write_file(CONSERVATION_MODE_PATH, value)
  if err then
    print("Error toggling conservation mode:", err)
  end
end

local function ToggleButton(icon, label, is_active, on_clicked)
  local button = Widget.Button({
    class_name = "toggle-button",
    child = Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Icon({ icon = icon }),
      Widget.Label({ label = label }),
    }),
  })

  if is_active then
    button:get_style_context():add_class("active")
  end

  if on_clicked then
    button.on_clicked = on_clicked
  end

  return button
end

local function Toggles()
  local conservationButton = nil
  local theme = Theme.get_default()

  astal.monitor_file(CONSERVATION_MODE_PATH, function(_, event)
    if conservationButton and event == "CHANGED" then
      local isEnabled = getConservationMode()
      local style_context = conservationButton:get_style_context()
      if isEnabled then
        style_context:add_class("active")
      else
        style_context:remove_class("active")
      end
    end
  end)

  return Widget.Box({
    orientation = "VERTICAL",
    spacing = 5,
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 5,
      homogeneous = true,
      Widget.Box({
        hexpand = true,
        child = ToggleButton("network-wireless-symbolic", "Wi-Fi"),
      }),
      Widget.Box({
        hexpand = true,
        child = ToggleButton("bluetooth-active-symbolic", "Bluetooth"),
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 5,
      homogeneous = true,
      Widget.Box({
        hexpand = true,
        child = ToggleButton("power-profile-balanced-symbolic", "Power Mode"),
      }),
      Widget.Box({
        hexpand = true,
        child = ToggleButton("night-light-symbolic", "Night Light"),
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 5,
      homogeneous = true,
      Widget.Box({
        hexpand = true,
        child = Widget.Button({
          setup = function(self)
            if theme.is_dark:get() then
              self:get_style_context():add_class("active")
            end
            theme.is_dark:subscribe(function(is_dark)
              local style_context = self:get_style_context()
              if is_dark then
                style_context:add_class("active")
              else
                style_context:remove_class("active")
              end
            end)
          end,
          class_name = "toggle-button",
          child = Widget.Box({
            orientation = "HORIZONTAL",
            spacing = 10,
            Widget.Icon({ icon = "dark-mode-symbolic" }),
            Widget.Label({ label = "Dark Style" }),
          }),
          on_clicked = function()
            theme:toggle_theme()
          end,
        }),
      }),
      Widget.Box({
        hexpand = true,
        child = Widget.Button({
          setup = function(self)
            conservationButton = self
            if getConservationMode() then
              self:get_style_context():add_class("active")
            end
          end,
          class_name = "toggle-button",
          child = Widget.Box({
            orientation = "HORIZONTAL",
            spacing = 10,
            Widget.Icon({ icon = os.getenv("PWD") .. "/icons/battery-powersave.svg" }),
            Widget.Label({ label = "Power Saver" }),
          }),
          on_clicked = toggleConservationMode,
        }),
      }),
    }),
  })
end

return function()
  return Toggles()
end
