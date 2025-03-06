local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Wp = astal.require("AstalWp")
local bind = astal.bind
local Debug = require("lua.lib.debug")
local timeout = astal.timeout
local Variable = require("astal.variable")

local SHOW_TIMEOUT = 1500

local function create_volume_indicator(device, class_name)
	return Widget.Box({
		class_name = class_name,
		visible = false,
		css = "min-width: 200px; min-height: 30px;",
		Widget.Box({
			class_name = "indicator",
			css = "min-width: 80px;",
			Widget.Icon({
				icon = bind(device, "volume-icon"),
			}),
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
				value = bind(device, "volume"),
				on_dragged = function(slider)
					device.volume = slider.value
				end,
			}),
		}),
	})
end

local function create_mute_indicator(device, class_name)
	return Widget.Box({
		class_name = class_name .. "-mute",
		visible = false,
		css = "min-width: 200px; min-height: 30px;",
		Widget.Icon({
			icon = bind(device, "volume-icon"),
		}),
		Widget.Label({
			label = "Muted",
			css = "margin-left: 8px;",
		}),
	})
end

local function create_osd_widget(current_timeout_ref)
	local speaker = Wp.get_default().audio.default_speaker
	local mic = Wp.get_default().audio.default_microphone

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
		setup = function(self)
			local speaker_vol = create_volume_indicator(speaker, "volume-indicator")
			local speaker_mute = create_mute_indicator(speaker, "volume-indicator")
			local mic_vol = create_volume_indicator(mic, "mic-indicator")
			local mic_mute = create_mute_indicator(mic, "mic-indicator")

			self:add(speaker_vol)
			self:add(speaker_mute)
			self:add(mic_vol)
			self:add(mic_mute)

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

			local speaker_volume_var = Variable.derive({ bind(speaker, "volume") }, function(vol)
				return vol
			end)

			local speaker_mute_var = Variable.derive({ bind(speaker, "mute") }, function(muted)
				return muted
			end)

			local mic_volume_var = Variable.derive({ bind(mic, "volume") }, function(vol)
				return vol
			end)

			local mic_mute_var = Variable.derive({ bind(mic, "mute") }, function(muted)
				return muted
			end)

			speaker_volume_var:subscribe(function()
				show_osd(speaker_vol)
			end)

			speaker_mute_var:subscribe(function(muted)
				show_osd(muted and speaker_mute or speaker_vol)
			end)

			mic_volume_var:subscribe(function()
				show_osd(mic_vol)
			end)

			mic_mute_var:subscribe(function(muted)
				show_osd(muted and mic_mute or mic_vol)
			end)

			self:hook(self, "destroy", function()
				speaker_volume_var:drop()
				speaker_mute_var:drop()
				mic_volume_var:drop()
				mic_mute_var:drop()
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
		setup = function(self)
			self:add(create_osd_widget(current_timeout_ref))
		end,
		on_destroy = function()
			if current_timeout_ref.timer then
				current_timeout_ref.timer = nil
			end
		end,
	})
end
