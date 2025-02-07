local Widget = require("astal.gtk3.widget")
local Volume = require("lua.widgets.QS.Volume")

local function Sliders()
  return Widget.Box({
    orientation = "VERTICAL",
    spacing = 10,
    Volume.create_output_slider(),
    Volume.create_input_slider(),
  })
end

return function()
  return Sliders()
end
