local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local GLib = astal.require("GLib")
local Gtk = astal.require("Gtk")
local Wp = astal.require("AstalWp")
local Variable = astal.Variable
local Debug = require("lua.lib.debug")
local Managers = require("lua.lib.managers")

_G.AUDIO_CONTROL_UPDATING = false

local show_output_devices = Variable(false)
local show_input_devices = Variable(false)

Managers.VariableManager.register(show_output_devices)
Managers.VariableManager.register(show_input_devices)

local function create_volume_control(type)
	local audio = Wp.get_default().audio
	if not audio then
		Debug.error("AudioControl", "Failed to get audio service")
		return Widget.Box({})
	end

	Managers.VariableManager.register(audio)

	local device = audio["default_" .. type]
	local volume_scale
	local volume = Variable(device and device.volume * 100 or 0)

	Managers.VariableManager.register(device)
	Managers.VariableManager.register(volume)

	volume_scale = Widget.Slider({
		class_name = "volume-slider",
		draw_value = false,
		hexpand = true,
		width_request = 200,
		orientation = Gtk.Orientation.HORIZONTAL,
		value = volume(),
		adjustment = Gtk.Adjustment({
			lower = 0,
			upper = 100,
			step_increment = 1,
			page_increment = 10,
		}),
		on_realize = function(self)
			if device then
				self:set_value(device.volume * 100)
			end
		end,
		on_value_changed = function(self)
			if not device then
				Debug.error("AudioControl", "No audio device available for volume control")
				return
			end

			local new_value = self:get_value() / 100
			if new_value >= 0 and new_value <= 1 then
				device.volume = new_value
				volume:set(self:get_value())
			end
		end,
	})

	if device then
		local volume_binding = bind(device, "volume")
		Managers.BindingManager.register(volume_binding)

		volume_binding:as(function(vol)
			if vol then
				volume:set(vol * 100)
				if volume_scale and volume_scale.set_value then
					_G.AUDIO_CONTROL_UPDATING = true
					volume_scale:set_value(vol * 100)
					_G.AUDIO_CONTROL_UPDATING = false
				end
			end
		end)

		local last_vol = device.volume
		GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 100, function()
			if device and device.volume and device.volume ~= last_vol then
				last_vol = device.volume
				_G.AUDIO_CONTROL_UPDATING = true
				volume:set(last_vol * 100)
				if volume_scale and volume_scale.set_value then
					volume_scale:set_value(last_vol * 100)
				end
				_G.AUDIO_CONTROL_UPDATING = false
			end
			return true
		end)
	end

	local default_device_binding = bind(audio, "default_" .. type)
	Managers.BindingManager.register(default_device_binding)

	default_device_binding:as(function(new_device)
		if new_device then
			device = new_device
			Managers.VariableManager.register(new_device)
			volume:set(device.volume * 100)
			volume_scale:set_value(device.volume * 100)
		end
	end)

	local device_mute_binding = bind(device, "mute")
	Managers.BindingManager.register(device_mute_binding)

	local volume_binding = bind(volume)
	Managers.BindingManager.register(volume_binding)

	return Widget.Box({
		orientation = "HORIZONTAL",
		spacing = 10,
		Widget.Button({
			class_name = "mute-button",
			on_clicked = function()
				if device then
					device.mute = not device.mute
				end
			end,
			child = Widget.Icon({
				icon = device_mute_binding:as(function(mute)
					if type == "speaker" then
						return mute and "audio-volume-muted-symbolic" or "audio-volume-high-symbolic"
					else
						return mute and "microphone-disabled-symbolic" or "microphone-sensitivity-high-symbolic"
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
				label = volume_binding:as(function(vol)
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

local function AudioOutputs()
	local audio = Wp.get_default().audio
	if not audio then
		Debug.error("AudioControl", "Failed to get audio service for outputs")
		return Widget.Box({})
	end

	Managers.VariableManager.register(audio)

	local show_devices_binding = bind(show_output_devices)
	local speakers_binding = bind(audio, "speakers")

	Managers.BindingManager.register(show_devices_binding)
	Managers.BindingManager.register(speakers_binding)

	return Widget.Box({
		class_name = "audio-outputs",
		orientation = "VERTICAL",
		spacing = 5,
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
					class_name = show_devices_binding:as(function(shown)
						return shown and "expanded" or ""
					end),
				}),
			}),
		}),
		Widget.Revealer({
			transition_duration = 200,
			transition_type = "SLIDE_DOWN",
			reveal_child = show_output_devices(),
			child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 5,
				class_name = "device-list",
				speakers_binding:as(function(speakers)
					if not speakers then
						return {}
					end

					local buttons = {}
					for _, speaker in ipairs(speakers) do
						Managers.VariableManager.register(speaker)
						table.insert(
							buttons,
							Widget.Button({
								child = Widget.Box({
									orientation = "HORIZONTAL",
									spacing = 10,
									Widget.Icon({ icon = "audio-speakers-symbolic" }),
									Widget.Label({
										label = speaker.description or "Unknown Device",
									}),
								}),
								on_clicked = function()
									speaker:set_is_default(true)
								end,
							})
						)
					end
					return buttons
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

	Managers.VariableManager.register(audio)

	local show_devices_binding = bind(show_input_devices)
	local microphones_binding = bind(audio, "microphones")

	Managers.BindingManager.register(show_devices_binding)
	Managers.BindingManager.register(microphones_binding)

	return Widget.Box({
		class_name = "microphone-inputs",
		orientation = "VERTICAL",
		spacing = 5,
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
					class_name = show_devices_binding:as(function(shown)
						return shown and "expanded" or ""
					end),
				}),
			}),
		}),
		Widget.Revealer({
			transition_duration = 200,
			transition_type = "SLIDE_DOWN",
			reveal_child = show_input_devices(),
			child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 5,
				class_name = "device-list",
				microphones_binding:as(function(microphones)
					if not microphones then
						return {}
					end

					local buttons = {}
					for _, mic in ipairs(microphones) do
						Managers.VariableManager.register(mic)
						table.insert(
							buttons,
							Widget.Button({
								child = Widget.Box({
									orientation = "HORIZONTAL",
									spacing = 10,
									Widget.Icon({ icon = "audio-input-microphone-symbolic" }),
									Widget.Label({
										label = mic.description or "Unknown Device",
									}),
								}),
								on_clicked = function()
									mic:set_is_default(true)
								end,
							})
						)
					end
					return buttons
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
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 15,
			css = "padding: 15px;",
			VolumeControls(),
			AudioOutputs(),
			MicrophoneInputs(),
			Settings(close_window),
		}),
		on_destroy = function()
			Managers.BindingManager.cleanup_all()
			Managers.VariableManager.cleanup_all()
		end,
	})

	return window
end

return AudioControlWindow
