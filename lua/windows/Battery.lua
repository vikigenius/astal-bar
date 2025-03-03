local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local Battery = astal.require("AstalBattery")
local PowerProfiles = astal.require("AstalPowerProfiles")
local GLib = astal.require("GLib")

local CONSERVATION_MODE_PATH = "/sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/VPC2004:00/conservation_mode"

local function getConservationMode()
  local content, err = astal.read_file(CONSERVATION_MODE_PATH)
  if err then
    return false
  end
  return tonumber(content) == 1
end

local function getBatteryDevice()
  local upower = Battery.UPower.new()
  local devices = upower:get_devices()

  for _, device in ipairs(devices) do
    if device:get_is_battery() and device:get_power_supply() then
      return device
    end
  end

  return upower:get_display_device()
end

local function formatTime(seconds)
  if seconds <= 0 then return "Fully charged" end

  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)

  if hours > 0 then
    return string.format("%d:%02d hours", hours, minutes)
  else
    return string.format("%d minutes", minutes)
  end
end

local function MainInfo(on_destroy_ref)
  local bat = getBatteryDevice()
  local time_info = Variable(""):poll(1000, function()
    local state = bat:get_state()
    if state == "PENDING_CHARGE" and getConservationMode() then
      return "Conservation mode enabled, waiting to charge"
    end

    if state == "CHARGING" then
      local time = bat:get_time_to_full()
      if time and time > 0 then
        return formatTime(time)
      end
      return "Calculating..."
    elseif state == "DISCHARGING" then
      local time = bat:get_time_to_empty()
      if time and time > 0 then
        return formatTime(time)
      end
      return "Calculating..."
    elseif state == "FULLY_CHARGED" then
      return "Fully charged"
    else
      return tostring(state)
    end
  end)

  on_destroy_ref.time_info = time_info

  return Widget.Box({
    class_name = "battery-main-info",
    Widget.Box({
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Icon({
        icon = bind(bat, "battery-icon-name"),
      }),
      Widget.Box({
        orientation = "VERTICAL",
        Widget.Label({
          label = bind(bat, "percentage"):as(function(p)
            return string.format("Battery %.0f%%", p * 100)
          end),
          xalign = 0,
        }),
        Widget.Label({
          label = time_info(),
          xalign = 0,
        }),
      }),
    }),
  })
end

local function BatteryInfo()
  local bat = getBatteryDevice()

  return Widget.Box({
    class_name = "battery-details",
    orientation = "VERTICAL",
    spacing = 5,
    Widget.Box({
      orientation = "HORIZONTAL",
      Widget.Label({ label = "Status:" }),
      Widget.Label({
        label = bind(bat, "state"):as(function(state)
          return state:gsub("^%l", string.upper):gsub("-", " ")
        end),
        xalign = 1,
        hexpand = true,
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      Widget.Label({ label = "Health:" }),
      Widget.Label({
        label = bind(bat, "capacity"):as(function(capacity)
          return string.format("%.1f%%", capacity * 100)
        end),
        xalign = 1,
        hexpand = true,
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      Widget.Label({ label = "Charge cycles:" }),
      Widget.Label({
        label = bind(bat, "charge-cycles"):as(function(cycles)
          return tostring(cycles or "N/A")
        end),
        xalign = 1,
        hexpand = true,
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      Widget.Label({ label = "Power draw:" }),
      Widget.Label({
        label = bind(bat, "energy-rate"):as(function(rate)
          return string.format("%.1f W", rate or 0)
        end),
        xalign = 1,
        hexpand = true,
      }),
    }),
    Widget.Box({
      orientation = "HORIZONTAL",
      Widget.Label({ label = "Voltage:" }),
      Widget.Label({
        label = bind(bat, "voltage"):as(function(voltage)
          return string.format("%.1f V", voltage or 0)
        end),
        xalign = 1,
        hexpand = true,
      }),
    }),
  })
end

local function PowerProfile(on_destroy_ref)
  local power = PowerProfiles.get_default()

  local function updateButtons(box, active_profile)
    for _, child in ipairs(box:get_children()) do
      local button_profile = child:get_label():lower():gsub(" ", "-")
      if button_profile == active_profile then
        child:get_style_context():add_class("active")
      else
        child:get_style_context():remove_class("active")
      end
    end
  end

  local buttons_box = Widget.Box({
    orientation = "HORIZONTAL",
    spacing = 5,
    homogeneous = true,
    Widget.Button({
      label = "Power Saver",
      on_clicked = function()
        power.active_profile = "power-saver"
      end,
    }),
    Widget.Button({
      label = "Balanced",
      on_clicked = function()
        power.active_profile = "balanced"
      end,
    }),
    Widget.Button({
      label = "Performance",
      on_clicked = function()
        power.active_profile = "performance"
      end,
    }),
    setup = function(self)
      updateButtons(self, power.active_profile)
    end,
  })

  local profile_binding = bind(power, "active-profile"):subscribe(function(profile)
    updateButtons(buttons_box, profile)
  end)
  on_destroy_ref.profile_binding = profile_binding

  local bat = getBatteryDevice()
  local profile_monitor = Variable(""):poll(1000, function()
    local state = bat:get_state()
    if state == "CHARGING" then
      power.active_profile = "performance"
    elseif state == "DISCHARGING" then
      power.active_profile = "balanced"
    end
  end)
  on_destroy_ref.profile_monitor = profile_monitor

  return Widget.Box({
    class_name = "power-profiles",
    orientation = "VERTICAL",
    spacing = 5,
    Widget.Label({
      label = "Power Mode",
      xalign = 0,
    }),
    buttons_box,
  })
end

local function ConservationMode()
  local function updateSwitchState(switch)
    local is_active = getConservationMode()
    switch:set_active(is_active)
    if is_active then
      switch:get_style_context():add_class("active")
    else
      switch:get_style_context():remove_class("active")
    end
  end

  local switch = Widget.Switch({
    active = getConservationMode(),
    on_state_set = function(self, state)
      local value = state and "1" or "0"
      astal.write_file_async(CONSERVATION_MODE_PATH, value, function(err)
        if err then
          print("Error setting conservation mode:", err)
          updateSwitchState(self)
        else
          if state then
            self:get_style_context():add_class("active")
          else
            self:get_style_context():remove_class("active")
          end
        end
      end)
      return true
    end,
    tooltip_text = "Limit battery charge to 80% to extend battery lifespan",
    setup = function(self)
      updateSwitchState(self)
    end,
  })

  astal.monitor_file(CONSERVATION_MODE_PATH, function(_, event)
    if event == "CHANGED" then
      updateSwitchState(switch)
    end
  end)

  return Widget.Box({
    class_name = "conservation-mode",
    orientation = "VERTICAL",
    spacing = 5,
    Widget.Label({
      label = "Conservation Mode",
      xalign = 0,
    }),
    switch,
  })
end

local function Settings(close_window)
  return Widget.Box({
    class_name = "settings",
    Widget.Button({
      label = "Power & battery settings",
      on_clicked = function()
        if close_window then
          close_window()
        end
        GLib.spawn_command_line_async(
          "env XDG_CURRENT_DESKTOP=GNOME gnome-control-center power"
        )
      end,
    }),
  })
end

local BatteryWindow = {}

function BatteryWindow.new(gdkmonitor)
  local Anchor = astal.require("Astal").WindowAnchor
  local window
  local on_destroy_ref = {}
  local is_closing = false

  local function close_window()
    if window and not is_closing then
      is_closing = true
      window:hide()
      is_closing = false
    end
  end

  window = Widget.Window({
    class_name = "BatteryWindow",
    gdkmonitor = gdkmonitor,
    anchor = Anchor.TOP + Anchor.RIGHT,
    child = Widget.Box({
      orientation = "VERTICAL",
      spacing = 10,
      css = "padding: 15px;",
      MainInfo(on_destroy_ref),
      BatteryInfo(),
      PowerProfile(on_destroy_ref),
      ConservationMode(),
      Settings(close_window),
    }),
  })

  return window
end

return BatteryWindow
