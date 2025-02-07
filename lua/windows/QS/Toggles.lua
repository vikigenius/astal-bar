local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Theme = require("lua.lib.theme")
local Variable = astal.Variable
local bind = astal.bind
local exec = astal.exec

local Network = require("lua.widgets.QS.Network")
local ConservationModeToggle = require("lua.widgets.QS.Conservation-Mode")

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

local function ExpandableToggle(icon, label, custom_menu)
  local show_menu = Variable(false)

  local menu_container = Widget.Revealer({
    transition_duration = 200,
    transition_type = "SLIDE_DOWN",
    reveal_child = show_menu(function(value)
      return value
    end),
    child = Widget.Box({
      class_name = "expanded-menu",
      orientation = "VERTICAL",
      spacing = 5,
      custom_menu or Widget.Label({ label = "Expanded menu placeholder" }),
    }),
  })

  local expand_button = Widget.Button({
    class_name = "expand-button",
    child = Widget.Icon({ icon = "pan-down-symbolic" }),
  })

  expand_button.on_clicked = function()
    show_menu:set(not show_menu:get())
  end


  return Widget.Box({
    class_name = "toggle-container",
    orientation = "VERTICAL",
    spacing = 2,
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 0,
      Widget.Button({
        class_name = "toggle-button with-arrow",
        hexpand = true,
        child = Widget.Box({
          orientation = "HORIZONTAL",
          spacing = 10,
          Widget.Icon({ icon = icon }),
          Widget.Label({ label = label }),
        }),
      }),
      expand_button,
    }),
    menu_container,
  })
end

local function Toggles()
  local theme = Theme.get_default()

  return Widget.Box({
    orientation = "VERTICAL",
    spacing = 10,
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      homogeneous = true,
      Widget.Box({
        class_name = "toggle-container with-arrow",
        hexpand = true,
        child = Network(),
      }),
      Widget.Box({
        class_name = "toggle-container with-arrow",
        hexpand = true,
        child = ExpandableToggle("bluetooth-active-symbolic", "Bluetooth"),
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      homogeneous = true,
      Widget.Box({
        hexpand = true,
        class_name = "toggle-container with-arrow",
        child = ExpandableToggle("power-profile-balanced-symbolic", "Power Mode"),
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
      ConservationModeToggle(),
    }),
  })
end

return function()
  return Toggles()
end
