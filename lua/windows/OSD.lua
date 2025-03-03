local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Wp = astal.require("AstalWp")
local bind = astal.bind

local timeout = astal.timeout

local SHOW_TIMEOUT = 1500

local function create_volume_indicator(device, class_name)
	return Widget.Box({
		class_name = class_name,
		visible = false,
		Widget.Box({
			class_name = "indicator",
			Widget.Icon({ icon = bind(device, "volume-icon") }),
			Widget.Label({
				label = bind(device, "volume"):as(function(vol)
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
				value = bind(device, "volume"),
			}),
		}),
	})
end

local function create_mute_indicator(device, class_name)
	return Widget.Box({
		class_name = class_name .. "-mute",
		visible = false,
		Widget.Icon({
			icon = bind(device, "volume-icon"),
		}),
		Widget.Label({
			label = "Muted",
		}),
	})
end

local function create_osd_widget(current_timeout_ref)
	local speaker = Wp.get_default().audio.default_speaker
	local mic = Wp.get_default().audio.default_microphone

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

			bind(speaker, "volume"):subscribe(function()
				show_osd(speaker_vol)
			end)

			bind(speaker, "mute"):subscribe(function(muted)
				show_osd(muted and speaker_mute or speaker_vol)
			end)

			bind(mic, "volume"):subscribe(function()
				show_osd(mic_vol)
			end)

			bind(mic, "mute"):subscribe(function(muted)
				show_osd(muted and mic_mute or mic_vol)
			end)
		end,
	})
end

return function(gdkmonitor)
	local Anchor = astal.require("Astal").WindowAnchor
	local current_timeout_ref = { timer = nil }

	return Widget.Window({
		class_name = "OSDWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM,
		create_osd_widget(current_timeout_ref),
		on_destroy = function()
			if current_timeout_ref.timer then
				current_timeout_ref.timer:cancel()
			end
		end,
	})
end
