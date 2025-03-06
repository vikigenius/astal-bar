local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local GLib = astal.require("GLib")
local Gtk = astal.require("Gtk")
local Wp = astal.require("AstalWp")
local Variable = astal.Variable
local Debug = require("lua.lib.debug")

_G.AUDIO_CONTROL_UPDATING = false

local show_output_devices = Variable(false)
local show_input_devices = Variable(false)

local function create_volume_control(type)
	local audio = Wp.get_default().audio
	if not audio then
		Debug.error("AudioControl", "Failed to get audio service")
		return Widget.Box({})
	end

	local device = audio["default_" .. type]
	if not device then
		Debug.error("AudioControl", "No default " .. type .. " device found")
		return Widget.Box({})
	end

	local device_volume = Variable(device.volume * 100)
	local device_mute = Variable(device.mute)

	local volume_scale = Widget.Slider({
		class_name = "volume-slider",
		draw_value = false,
		hexpand = true,
		width_request = 200,
		orientation = Gtk.Orientation.HORIZONTAL,
		value = device_volume:get(),
		adjustment = Gtk.Adjustment({
			lower = 0,
			upper = 100,
			step_increment = 1,
			page_increment = 10,
		}),
		on_value_changed = function(self)
			if not device then
				return
			end
			local new_value = self:get_value() / 100
			if new_value >= 0 and new_value <= 1 then
				_G.AUDIO_CONTROL_UPDATING = true
				device.volume = new_value
				device_volume:set(self:get_value())
				_G.AUDIO_CONTROL_UPDATING = false
			end
		end,
	})

	return Widget.Box({
		orientation = "HORIZONTAL",
		spacing = 10,
		setup = function(self)
			self:hook(device, "notify::volume", function()
				if not _G.AUDIO_CONTROL_UPDATING then
					local new_value = device.volume * 100
					device_volume:set(new_value)
					volume_scale:set_value(new_value)
				end
			end)

			self:hook(device, "notify::mute", function()
				device_mute:set(device.mute)
			end)

			self:hook(self, "destroy", function()
				device_volume:drop()
				device_mute:drop()
			end)
		end,
		Widget.Button({
			class_name = "mute-button",
			on_clicked = function()
				if device then
					device.mute = not device.mute
				end
			end,
			child = Widget.Icon({
				icon = bind(device_mute):as(function(muted)
					if type == "speaker" then
						return muted and "audio-volume-muted-symbolic" or "audio-volume-high-symbolic"
					else
						return muted and "microphone-disabled-symbolic" or "microphone-sensitivity-high-symbolic"
					end
				end),
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 5,
			hexpand = true,
			volume_scale,
			Widget.Label({
				label = bind(device_volume):as(function(vol)
					return string.format("%d%%", math.floor(vol or 0))
				end),
				width_chars = 4,
				xalign = 1,
			}),
		}),
	})
end

local function VolumeControls()
	return Widget.Box({
		class_name = "volume-controls",
		orientation = "VERTICAL",
		spacing = 10,
		create_volume_control("speaker"),
		create_volume_control("microphone"),
	})
end

local function create_device_list(devices, icon_name)
	local buttons = {}
	for _, device in ipairs(devices or {}) do
		table.insert(
			buttons,
			Widget.Button({
				child = Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 10,
					Widget.Icon({ icon = icon_name }),
					Widget.Label({
						label = device.description or "Unknown Device",
					}),
				}),
				on_clicked = function()
					device:set_is_default(true)
				end,
			})
		)
	end
	return buttons
end

local function AudioOutputs()
	local audio = Wp.get_default().audio
	if not audio then
		Debug.error("AudioControl", "Failed to get audio service for outputs")
		return Widget.Box({})
	end

	local expanded_class = Variable.derive({ show_output_devices }, function(shown)
		return shown and "expanded" or ""
	end)

	return Widget.Box({
		class_name = "audio-outputs",
		orientation = "VERTICAL",
		spacing = 5,
		setup = function(self)
			self:hook(self, "destroy", function()
				expanded_class:drop()
			end)
		end,
		Widget.Button({
			class_name = "device-selector",
			on_clicked = function()
				show_output_devices:set(not show_output_devices:get())
			end,
			child = Widget.Box({
				orientation = "HORIZONTAL",
				spacing = 10,
				Widget.Icon({ icon = "audio-speakers-symbolic" }),
				Widget.Box({
					hexpand = true,
					Widget.Label({
						label = "Output",
						xalign = 0,
					}),
				}),
				Widget.Icon({
					icon = "pan-down-symbolic",
					class_name = expanded_class(),
				}),
			}),
		}),
		Widget.Revealer({
			transition_duration = 200,
			transition_type = "SLIDE_DOWN",
			reveal_child = bind(show_output_devices),
			child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 5,
				class_name = "device-list",
				bind(audio, "speakers"):as(function(speakers)
					return create_device_list(speakers, "audio-speakers-symbolic")
				end),
			}),
		}),
	})
end

local function MicrophoneInputs()
	local audio = Wp.get_default().audio
	if not audio then
		Debug.error("AudioControl", "Failed to get audio service for inputs")
		return Widget.Box({})
	end

	local expanded_class = Variable.derive({ show_input_devices }, function(shown)
		return shown and "expanded" or ""
	end)

	return Widget.Box({
		class_name = "microphone-inputs",
		orientation = "VERTICAL",
		spacing = 5,
		setup = function(self)
			self:hook(self, "destroy", function()
				expanded_class:drop()
			end)
		end,
		Widget.Button({
			class_name = "device-selector",
			on_clicked = function()
				show_input_devices:set(not show_input_devices:get())
			end,
			child = Widget.Box({
				orientation = "HORIZONTAL",
				spacing = 10,
				Widget.Icon({ icon = "audio-input-microphone-symbolic" }),
				Widget.Box({
					hexpand = true,
					Widget.Label({
						label = "Input",
						xalign = 0,
					}),
				}),
				Widget.Icon({
					icon = "pan-down-symbolic",
					class_name = expanded_class(),
				}),
			}),
		}),
		Widget.Revealer({
			transition_duration = 200,
			transition_type = "SLIDE_DOWN",
			reveal_child = bind(show_input_devices),
			child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 5,
				class_name = "device-list",
				bind(audio, "microphones"):as(function(microphones)
					return create_device_list(microphones, "audio-input-microphone-symbolic")
				end),
			}),
		}),
	})
end

local function Settings(close_window)
	return Widget.Box({
		class_name = "settings",
		Widget.Button({
			label = "Sound Settings",
			on_clicked = function()
				if close_window then
					close_window()
				end
				GLib.spawn_command_line_async("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center sound")
			end,
		}),
	})
end

local AudioControlWindow = {}

function AudioControlWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("AudioControl", "No monitor available")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local window
	local is_closing = false

	local function close_window()
		if window and not is_closing then
			is_closing = true
			window:hide()
			is_closing = false
		end
	end

	window = Widget.Window({
		class_name = "AudioControlWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		setup = function(self)
			self:hook(self, "destroy", function()
				show_output_devices:drop()
				show_input_devices:drop()
			end)
		end,
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 15,
			css = "padding: 15px;",
			VolumeControls(),
			AudioOutputs(),
			MicrophoneInputs(),
			Settings(close_window),
		}),
	})

	return window
end

return AudioControlWindow
