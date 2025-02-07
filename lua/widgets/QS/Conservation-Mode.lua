local astal = require("astal")
local Widget = require("astal.gtk3.widget")

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

local function ConservationModeToggle()
  local button = Widget.Button({
    setup = function(self)
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
  })

  astal.monitor_file(CONSERVATION_MODE_PATH, function(_, event)
    if event == "CHANGED" then
      local isEnabled = getConservationMode()
      local style_context = button:get_style_context()
      if isEnabled then
        style_context:add_class("active")
      else
        style_context:remove_class("active")
      end
    end
  end)

  return Widget.Box({
    hexpand = true,
    child = button
  })
end

return ConservationModeToggle
