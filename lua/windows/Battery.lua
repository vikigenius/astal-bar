local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local Battery = astal.require("AstalBattery")
local PowerProfiles = astal.require("AstalPowerProfiles")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")
local Managers = require("lua.lib.managers")

local CONSERVATION_MODE_PATH = "/sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/VPC2004:00/conservation_mode"

local function getConservationMode()
	local content, err = astal.read_file(CONSERVATION_MODE_PATH)
	if err then
		Debug.error("Battery", "Failed to read conservation mode: %s", err)
		return false
	end
	return tonumber(content) == 1
end

local function getBatteryDevice()
	local upower = Battery.UPower.new()
	if not upower then
		Debug.error("Battery", "Failed to initialize UPower")
		return nil
	end

	Managers.VariableManager.register(upower)

	local devices = upower:get_devices()
	if not devices then
		Debug.error("Battery", "Failed to get battery devices")
		return nil
	end

	for _, device in ipairs(devices) do
		if device:get_is_battery() and device:get_power_supply() then
			Managers.VariableManager.register(device)
			return device
		end
	end

	local display_device = upower:get_display_device()
	if not display_device then
		Debug.error("Battery", "No battery device found")
		return nil
	end
	Managers.VariableManager.register(display_device)
	return display_device
end

local function formatTime(seconds)
	if seconds <= 0 then
		return "Fully charged"
	end

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
	if not bat then
		Debug.error("Battery", "Cannot create MainInfo: no battery device")
		return Widget.Box({})
	end

	local time_info = Variable(""):poll(1000, function()
		local state = bat:get_state()
		if not state then
			Debug.error("Battery", "Failed to get battery state")
			return "Unknown"
		end

		if state == "PENDING_CHARGE" and getConservationMode() then
			return "Conservation mode enabled, waiting to charge"
		end

		if state == "CHARGING" or state == "DISCHARGING" then
			local time = state == "CHARGING" and bat:get_time_to_full() or bat:get_time_to_empty()
			if not time then
				Debug.error("Battery", "Failed to get battery time estimation")
				return "Calculating..."
			end
			if time > 0 then
				return formatTime(time)
			end
			return "Calculating..."
		end
		return tostring(state)
	end)

	Managers.VariableManager.register(time_info)
	on_destroy_ref.time_info = time_info

	local battery_icon_binding = bind(bat, "battery-icon-name")
	local percentage_binding = bind(bat, "percentage")
	local time_info_binding = bind(time_info)

	Managers.BindingManager.register(battery_icon_binding)
	Managers.BindingManager.register(percentage_binding)
	Managers.BindingManager.register(time_info_binding)

	return Widget.Box({
		class_name = "battery-main-info",
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 10,
			Widget.Icon({
				icon = battery_icon_binding,
			}),
			Widget.Box({
				orientation = "VERTICAL",
				Widget.Label({
					label = percentage_binding:as(function(p)
						if not p then
							Debug.error("Battery", "Failed to get battery percentage")
							return "Battery N/A"
						end
						return string.format("Battery %.0f%%", p * 100)
					end),
					xalign = 0,
				}),
				Widget.Label({
					label = time_info_binding,
					xalign = 0,
				}),
			}),
		}),
	})
end

local function BatteryInfo()
	local bat = getBatteryDevice()
	if not bat then
		Debug.error("Battery", "Cannot create BatteryInfo: no battery device")
		return Widget.Box({})
	end

	local state_binding = bind(bat, "state")
	local capacity_binding = bind(bat, "capacity")
	local cycles_binding = bind(bat, "charge-cycles")
	local rate_binding = bind(bat, "energy-rate")
	local voltage_binding = bind(bat, "voltage")

	Managers.BindingManager.register(state_binding)
	Managers.BindingManager.register(capacity_binding)
	Managers.BindingManager.register(cycles_binding)
	Managers.BindingManager.register(rate_binding)
	Managers.BindingManager.register(voltage_binding)

	return Widget.Box({
		class_name = "battery-details",
		orientation = "VERTICAL",
		spacing = 5,
		Widget.Box({
			orientation = "HORIZONTAL",
			Widget.Label({ label = "Status:" }),
			Widget.Label({
				label = state_binding:as(function(state)
					if not state then
						Debug.error("Battery", "Failed to get battery state")
						return "Unknown"
					end
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
				label = capacity_binding:as(function(capacity)
					if not capacity then
						Debug.error("Battery", "Failed to get battery capacity")
						return "N/A"
					end
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
				label = cycles_binding:as(function(cycles)
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
				label = rate_binding:as(function(rate)
					if not rate then
						Debug.error("Battery", "Failed to get power draw rate")
						return "N/A"
					end
					return string.format("%.1f W", rate)
				end),
				xalign = 1,
				hexpand = true,
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			Widget.Label({ label = "Voltage:" }),
			Widget.Label({
				label = voltage_binding:as(function(voltage)
					if not voltage then
						Debug.error("Battery", "Failed to get battery voltage")
						return "N/A"
					end
					return string.format("%.1f V", voltage)
				end),
				xalign = 1,
				hexpand = true,
			}),
		}),
	})
end

local function PowerProfile(on_destroy_ref)
	local power = PowerProfiles.get_default()
	if not power then
		Debug.error("Battery", "Failed to initialize PowerProfiles")
		return Widget.Box({})
	end

	Managers.VariableManager.register(power)

	local function updateButtons(box, active_profile)
		if not box or not active_profile then
			Debug.error("Battery", "Invalid arguments for updateButtons")
			return
		end
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
				if not power then
					return
				end
				power.active_profile = "power-saver"
			end,
		}),
		Widget.Button({
			label = "Balanced",
			on_clicked = function()
				if not power then
					return
				end
				power.active_profile = "balanced"
			end,
		}),
		Widget.Button({
			label = "Performance",
			on_clicked = function()
				if not power then
					return
				end
				power.active_profile = "performance"
			end,
		}),
		setup = function(self)
			if power and power.active_profile then
				updateButtons(self, power.active_profile)
			end
		end,
	})

	local profile_binding = bind(power, "active-profile"):subscribe(function(profile)
		updateButtons(buttons_box, profile)
	end)
	Managers.BindingManager.register(profile_binding)
	on_destroy_ref.profile_binding = profile_binding

	local bat = getBatteryDevice()
	local profile_monitor = Variable(""):poll(1000, function()
		if not bat or not power then
			return
		end
		local state = bat:get_state()
		if state == "CHARGING" then
			power.active_profile = "performance"
		elseif state == "DISCHARGING" then
			power.active_profile = "balanced"
		end
	end)
	Managers.VariableManager.register(profile_monitor)
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
					Debug.error("Battery", "Failed to set conservation mode: %s", err)
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
				GLib.spawn_command_line_async("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center power")
			end,
		}),
	})
end

local BatteryWindow = {}

function BatteryWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Battery", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

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
		on_destroy = function()
			if on_destroy_ref.time_info then
				Managers.VariableManager.cleanup(on_destroy_ref.time_info)
			end
			if on_destroy_ref.profile_binding then
				Managers.BindingManager.cleanup(on_destroy_ref.profile_binding)
			end
			if on_destroy_ref.profile_monitor then
				Managers.VariableManager.cleanup(on_destroy_ref.profile_monitor)
			end
			Managers.BindingManager.cleanup_all()
			Managers.VariableManager.cleanup_all()
		end,
	})

	return window
end

return BatteryWindow
