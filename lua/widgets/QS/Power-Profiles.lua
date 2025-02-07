local astal = require("astal")
local bind = astal.bind
local Variable = astal.Variable
local PowerProfiles = astal.require("AstalPowerProfiles")
local Widget = require("astal.gtk3.widget")

local PowerProfilesWidget = {}
local power = PowerProfiles.get_default()
local show_profiles_list = Variable(false)

local AVAILABLE_PROFILES = {
  "power-saver",
  "balanced",
  "performance"
}

local function get_profile_name(profile)
  if profile == "power-saver" then
    return "Power Saver"
  elseif profile == "balanced" then
    return "Balanced"
  elseif profile == "performance" then
    return "Performance"
  end
  return profile
end

local function get_profile_icon(profile)
  if profile == "power-saver" then
    return "power-profile-power-saver-symbolic"
  elseif profile == "balanced" then
    return "power-profile-balanced-symbolic"
  elseif profile == "performance" then
    return "power-profile-performance-symbolic"
  end
  return "power-profile-balanced-symbolic"
end

PowerProfilesWidget.ProfilesList = function()
  return Widget.Box({
    class_name = "expanded-menu",
    orientation = "VERTICAL",
    spacing = 5,
    bind(power, "active-profile"):as(function(active_profile)
      local buttons = {}
      for _, profile in ipairs(AVAILABLE_PROFILES) do
        local is_active = profile == "performance"

        table.insert(buttons, Widget.Button({
          class_name = "profile-item" .. (is_active and " active" or ""),
          on_clicked = function()
            power.active_profile = profile
          end,
          child = Widget.Box({
            orientation = "HORIZONTAL",
            spacing = 10,
            Widget.Icon({ icon = get_profile_icon(profile) }),
            Widget.Label({ label = get_profile_name(profile) }),
          }),
        }))
      end
      return buttons
    end),
  })
end

PowerProfilesWidget.ToggleButton = function()
  local expand_button = Widget.Button({
    class_name = "expand-button",
    child = Widget.Icon({ icon = "pan-down-symbolic" }),
  })

  expand_button.on_clicked = function()
    show_profiles_list:set(not show_profiles_list:get())
  end

  local toggle_button = Widget.Button({
    class_name = "toggle-button with-arrow",
    hexpand = true,
    setup = function(self)
      if power.active_profile == "performance" then
        self:get_style_context():add_class("active")
      end
      bind(power, "active-profile"):subscribe(function(profile)
        local style_context = self:get_style_context()
        if profile == "performance" then
          style_context:add_class("active")
        else
          style_context:remove_class("active")
        end
      end)
    end,
    child = Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Icon({
        icon = bind(power, "active-profile"):as(function(profile)
          return get_profile_icon(profile)
        end),
      }),
      Widget.Label({
        label = bind(power, "active-profile"):as(function(profile)
          return get_profile_name(profile)
        end),
      }),
    }),
  })

  toggle_button.on_clicked = function()
    -- Toggle between performance and balanced
    if power.active_profile == "performance" then
      power.active_profile = "balanced"
    else
      power.active_profile = "performance"
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
    PowerProfilesWidget.ToggleButton(),
    Widget.Revealer({
      transition_duration = 200,
      transition_type = "SLIDE_DOWN",
      reveal_child = show_profiles_list(function(value)
        return value
      end),
      PowerProfilesWidget.ProfilesList(),
    }),
  })
end
