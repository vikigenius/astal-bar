local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Variable = astal.Variable
local bind = astal.bind
local GLib = astal.require("GLib")
local Mpris = astal.require("AstalMpris")
local Tray = astal.require("AstalTray")
local Network = astal.require("AstalNetwork")
local Battery = astal.require("AstalBattery")
local Wp = astal.require("AstalWp")
local Debug = require("lua.lib.debug")
local Managers = require("lua.lib.managers")

local Workspaces = require("lua.widgets.Workspaces")
local ActiveClient = require("lua.widgets.ActiveClient")
local Vitals = require("lua.widgets.Vitals")

local map = require("lua.lib.common").map

local active_variables = {}
local github_window = nil
local audio_window = nil
local network_window = nil
local battery_window = nil

local function safe_bind(obj, prop)
	if not obj then
		Debug.error("Bar", "Failed to bind: object is nil")
		return nil
	end

	local success, binding = pcall(function()
		return bind(obj, prop)
	end)

	if not success then
		return nil
	end

	if binding then
		Managers.BindingManager.register(binding)
	end

	return binding
end

local function SysTray()
	local tray = Tray.get_default()
	Managers.VariableManager.register(tray)

	local tray_binding = bind(tray, "items")
	Managers.BindingManager.register(tray_binding)

	return Widget.Box({
		class_name = "SysTray",
		tray_binding:as(function(items)
			return map(items, function(item)
				local tooltip_binding = bind(item, "tooltip_markup")
				local menu_model_binding = bind(item, "menu-model")
				local action_group_binding = bind(item, "action-group")
				local gicon_binding = bind(item, "gicon")

				Managers.BindingManager.register(tooltip_binding)
				Managers.BindingManager.register(menu_model_binding)
				Managers.BindingManager.register(action_group_binding)
				Managers.BindingManager.register(gicon_binding)

				return Widget.MenuButton({
					tooltip_markup = tooltip_binding,
					use_popover = false,
					menu_model = menu_model_binding,
					action_group = action_group_binding:as(function(ag)
						return { "dbusmenu", ag }
					end),
					Widget.Icon({
						gicon = gicon_binding,
					}),
				})
			end)
		end),
	})
end

local function Media()
	local player = Mpris.Player.new("spotify")
	Managers.VariableManager.register(player)

	local available_binding = safe_bind(player, "available")
	local cover_binding = safe_bind(player, "cover-art")
	local metadata_binding = safe_bind(player, "metadata")

	return Widget.Box({
		class_name = "Media",
		visible = available_binding,
		Widget.Box({
			class_name = "Cover",
			valign = "CENTER",
			css = cover_binding and cover_binding:as(function(cover)
				return cover and "background-image: url('" .. cover .. "');" or ""
			end) or "",
		}),
		Widget.Label({
			label = metadata_binding and metadata_binding:as(function()
				return string.format("%s - %s", player.title or "", player.artist or "")
			end) or "",
		}),
	})
end

local function Time(format)
	local time = Variable(""):poll(1000, function()
		local success, datetime = pcall(function()
			return GLib.DateTime.new_now_local():format(format)
		end)
		return success and datetime or ""
	end)

	table.insert(active_variables, time)
	Managers.VariableManager.register(time)

	local time_binding = bind(time)
	Managers.BindingManager.register(time_binding)

	return Widget.Label({
		class_name = "Time",
		on_destroy = function()
			time:drop()
			for i, v in ipairs(active_variables) do
				if v == time then
					table.remove(active_variables, i)
					break
				end
			end
			Managers.VariableManager.cleanup(time)
			Managers.BindingManager.cleanup(time_binding)
		end,
		label = time(),
	})
end

local function GithubActivity()
	local window_visible = false
	local github_window = nil

	local function toggle_github_window()
		if window_visible and github_window then
			github_window:hide()
			window_visible = false
		else
			if not github_window then
				local GithubWindow = require("lua.windows.Github")
				github_window = GithubWindow.new()
			end
			github_window:show_all()
			window_visible = true
		end
	end

	return Widget.Button({
		class_name = "github-button",
		on_clicked = toggle_github_window,
		child = Widget.Icon({
			icon = os.getenv("PWD") .. "/icons/github-symbolic.svg",
			tooltip_text = "GitHub Activity",
		}),
	})
end

local function AudioControl(monitor)
	local audio = Wp.get_default().audio
	local speaker = audio and audio.default_speaker
	local mic = audio and audio.default_microphone
	local window_visible = false
	local audio_window = nil

	Managers.VariableManager.register(audio)
	Managers.VariableManager.register(speaker)
	Managers.VariableManager.register(mic)

	local function toggle_audio_window()
		if window_visible and audio_window then
			audio_window:hide()
			window_visible = false
		else
			if not audio_window then
				local AudioControlWindow = require("lua.windows.AudioControl")
				audio_window = AudioControlWindow.new(monitor)
			end
			if audio_window then
				audio_window:show_all()
			end
			window_visible = true
		end
	end

	local mic_volume_icon_binding = safe_bind(mic, "volume-icon")
	local mic_volume_binding = safe_bind(mic, "volume")
	local speaker_volume_binding = safe_bind(speaker, "volume")
	local speaker_volume_icon_binding = safe_bind(speaker, "volume-icon")

	return Widget.Button({
		class_name = "audio-button",
		on_clicked = toggle_audio_window,
		Widget.Box({
			spacing = 10,
			Widget.Icon({
				icon = mic_volume_icon_binding,
				tooltip_text = mic_volume_binding and mic_volume_binding:as(function(v)
					return string.format("Microphone Volume: %.0f%%", (v or 0) * 100)
				end),
			}),
			Widget.Icon({
				tooltip_text = speaker_volume_binding and speaker_volume_binding:as(function(v)
					return string.format("Audio Volume: %.0f%%", (v or 0) * 100)
				end),
				icon = speaker_volume_icon_binding,
			}),
		}),
	})
end

local function Wifi(monitor)
	local network = Network.get_default()
	Managers.VariableManager.register(network)

	local wifi_binding = bind(network, "wifi")
	Managers.BindingManager.register(wifi_binding)

	local window_visible = false
	local network_window = nil

	local function toggle_network_window()
		if window_visible and network_window then
			network_window:hide()
			window_visible = false
		else
			if not network_window then
				local NetworkWindow = require("lua.windows.Network")
				network_window = NetworkWindow.new(monitor)
			end
			if network_window then
				network_window:show_all()
			end
			window_visible = true
		end
	end

	return Widget.Button({
		class_name = "wifi-button",
		visible = wifi_binding:as(function(v)
			return v ~= nil
		end),
		on_clicked = toggle_network_window,
		wifi_binding:as(function(w)
			local ssid_binding = bind(w, "ssid")
			local icon_binding = bind(w, "icon-name")

			Managers.BindingManager.register(ssid_binding)
			Managers.BindingManager.register(icon_binding)

			return Widget.Icon({
				tooltip_text = ssid_binding:as(tostring),
				class_name = "Wifi",
				icon = icon_binding,
			})
		end),
	})
end

local function BatteryLevel(monitor)
	local bat = Battery.get_default()
	Managers.VariableManager.register(bat)

	local is_present_binding = bind(bat, "is-present")
	local icon_binding = bind(bat, "battery-icon-name")
	local percentage_binding = bind(bat, "percentage")

	Managers.BindingManager.register(is_present_binding)
	Managers.BindingManager.register(icon_binding)
	Managers.BindingManager.register(percentage_binding)

	local window_visible = false
	local battery_window = nil

	local function toggle_battery_window()
		if window_visible and battery_window then
			battery_window:hide()
			window_visible = false
		else
			if not battery_window then
				local BatteryWindow = require("lua.windows.Battery")
				battery_window = BatteryWindow.new(monitor)
			end
			if battery_window then
				battery_window:show_all()
			end
			window_visible = true
		end
	end

	return Widget.Button({
		class_name = "battery-button",
		visible = is_present_binding,
		on_clicked = toggle_battery_window,
		Widget.Box({
			Widget.Icon({
				icon = icon_binding,
				css = "padding-right: 5pt;",
			}),
			Widget.Label({
				label = percentage_binding:as(function(p)
					return tostring(math.floor(p * 100)) .. " %"
				end),
			}),
		}),
	})
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Bar", "No monitor available")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor

	local bar = Widget.Window({
		class_name = "Bar",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.LEFT + Anchor.RIGHT,
		exclusivity = "EXCLUSIVE",
		on_destroy = function()
			for _, var in ipairs(active_variables) do
				if var.drop then
					var:drop()
				end
			end
			active_variables = {}

			Managers.BindingManager.cleanup_all()
			Managers.VariableManager.cleanup_all()

			if github_window then
				github_window:destroy()
			end
			if audio_window then
				audio_window:destroy()
			end
			if network_window then
				network_window:destroy()
			end
			if battery_window then
				battery_window:destroy()
			end
		end,
		Widget.CenterBox({
			Widget.Box({
				halign = "START",
				ActiveClient(),
			}),
			Widget.Box({
				Time("%A %d, %H:%M"),
				Media(),
			}),
			Widget.Box({
				halign = "END",
				GithubActivity(),
				Vitals(),
				SysTray(),
				AudioControl(gdkmonitor),
				Wifi(gdkmonitor),
				BatteryLevel(gdkmonitor),
			}),
		}),
	})

	return bar
end
