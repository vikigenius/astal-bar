local Widget = require("astal.gtk3.widget")
local Gtk = require("astal.gtk3").Gtk

local Header = require("lua.windows.QS.Header")
local Toggles = require("lua.windows.QS.Toggles")

local function Sliders()
  return Widget.Box({
    orientation = "VERTICAL",
    spacing = 10,
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Icon({ icon = "audio-volume-high-symbolic" }),
      Gtk.Scale({
        orientation = Gtk.Orientation.HORIZONTAL,
        hexpand = true,
        draw_value = false,
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Icon({ icon = "audio-input-microphone-symbolic" }),
      Gtk.Scale({
        orientation = Gtk.Orientation.HORIZONTAL,
        hexpand = true,
        draw_value = false,
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Icon({ icon = "display-brightness-symbolic" }),
      Gtk.Scale({
        orientation = Gtk.Orientation.HORIZONTAL,
        hexpand = true,
        draw_value = false,
      }),
    }),
  })
end

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
