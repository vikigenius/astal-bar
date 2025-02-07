local Widget = require("astal.gtk3.widget")
local Gtk = require("astal.gtk3").Gtk

local Sliders = require("lua.windows.QS.Sliders")
local Header = require("lua.windows.QS.Header")
local Toggles = require("lua.windows.QS.Toggles")

local function QuickSettings()
  return Widget.Box({
    class_name = "QuickSettings",
    orientation = "VERTICAL",
    spacing = 15,
    css = "padding: 15px;",
    Header(),
    Sliders(),
    Toggles(),
  })
end

return function()
  return QuickSettings()
end
