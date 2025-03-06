local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Wp = astal.require("AstalWp")
local bind = astal.bind
local Debug = require("lua.lib.debug")
local timeout = astal.timeout
local Managers = require("lua.lib.managers")

local SHOW_TIMEOUT = 1500

local function create_volume_indicator(device, class_name)
	local volume_icon_binding = bind(device, "volume-icon")
	local volume_binding = bind(device, "volume")

	Managers.BindingManager.register(volume_icon_binding)
	Managers.BindingManager.register(volume_binding)

	return Widget.Box({
		class_name = class_name,
		visible = false,
		Widget.Box({
			class_name = "indicator",
			Widget.Icon({ icon = volume_icon_binding }),
			Widget.Label({
				label = volume_binding:as(function(vol)
					return string.format("%d%%", math.floor((vol or 0) * 100))
				end),
			}),
		}),
		Widget.Box({
			class_name = "slider-container",
			css = "min-width: 140px;",
			Widget.Slider({
				class_name = "volume-slider",
				hexpand = true,
				on_dragged = function(slider)
					device.volume = slider.value
				end,
				value = volume_binding,
			}),
		}),
	})
end

local function create_mute_indicator(device, class_name)
	local volume_icon_binding = bind(device, "volume-icon")
	Managers.BindingManager.register(volume_icon_binding)

	return Widget.Box({
		class_name = class_name .. "-mute",
		visible = false,
		Widget.Icon({
			icon = volume_icon_binding,
		}),
		Widget.Label({
			label = "Muted",
		}),
	})
end

local function create_osd_widget(current_timeout_ref)
	local speaker = Wp.get_default().audio.default_speaker
	local mic = Wp.get_default().audio.default_microphone

	Managers.VariableManager.register(speaker)
	Managers.VariableManager.register(mic)

	if not speaker or not mic then
		Debug.error(
			"OSD",
			"Failed to get audio devices - Speaker: %s, Mic: %s",
			speaker and "OK" or "NULL",
			mic and "OK" or "NULL"
		)
	end

	return Widget.Box({
		class_name = "OSD",
		vertical = true,
		create_volume_indicator(speaker, "volume-indicator"),
		create_mute_indicator(speaker, "volume-indicator"),
		create_volume_indicator(mic, "mic-indicator"),
		create_mute_indicator(mic, "mic-indicator"),
		setup = function(self)
			local speaker_vol = self.children[1]
			local speaker_mute = self.children[2]
			local mic_vol = self.children[3]
			local mic_mute = self.children[4]

			local function hide_all()
				speaker_vol.visible = false
				mic_vol.visible = false
				speaker_mute.visible = false
				mic_mute.visible = false
			end

			local function show_osd(widget)
				if _G.AUDIO_CONTROL_UPDATING then
					Debug.debug("OSD", "OSD update blocked: AUDIO_CONTROL_UPDATING is true")
					return
				end
				hide_all()
				widget.visible = true

				if current_timeout_ref.timer then
					current_timeout_ref.timer:cancel()
				end

				current_timeout_ref.timer = timeout(SHOW_TIMEOUT, function()
					widget.visible = false
					current_timeout_ref.timer = nil
				end)
			end

			local volume_binding = bind(speaker, "volume")
			local mute_binding = bind(speaker, "mute")
			local mic_volume_binding = bind(mic, "volume")
			local mic_mute_binding = bind(mic, "mute")

			Managers.BindingManager.register(volume_binding)
			Managers.BindingManager.register(mute_binding)
			Managers.BindingManager.register(mic_volume_binding)
			Managers.BindingManager.register(mic_mute_binding)

			volume_binding:subscribe(function(vol)
				show_osd(speaker_vol)
			end)

			mute_binding:subscribe(function(muted)
				show_osd(muted and speaker_mute or speaker_vol)
			end)

			mic_volume_binding:subscribe(function(vol)
				show_osd(mic_vol)
			end)

			mic_mute_binding:subscribe(function(muted)
				show_osd(muted and mic_mute or mic_vol)
			end)
		end,
	})
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("OSD", "Failed to initialize OSD: gdkmonitor is nil")
		return nil
	end

	local current_timeout_ref = { timer = nil }
	local Anchor = astal.require("Astal").WindowAnchor

	return Widget.Window({
		class_name = "OSDWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM,
		create_osd_widget(current_timeout_ref),
		on_destroy = function()
			if current_timeout_ref.timer then
				current_timeout_ref.timer = nil
			end
			Managers.BindingManager.cleanup_all()
			Managers.VariableManager.cleanup_all()
		end,
	})
end
