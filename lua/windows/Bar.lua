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

local Workspaces = require("lua.widgets.Workspaces")
local ActiveClient = require("lua.widgets.ActiveClient")
local Vitals = require("lua.widgets.Vitals")

local map = require("lua.lib.common").map

local active_variables = {}

local function safe_bind(obj, prop)
	if not obj then
		return nil
	end

	local success, binding = pcall(function()
		return bind(obj, prop)
	end)

	if not success then
		print("Binding failed:", binding)
		return nil
	end

	return binding
end

local function SysTray()
	local tray = Tray.get_default()

	return Widget.Box({
		class_name = "SysTray",
		bind(tray, "items"):as(function(items)
			return map(items, function(item)
				return Widget.MenuButton({
					tooltip_markup = bind(item, "tooltip_markup"),
					use_popover = false,
					menu_model = bind(item, "menu-model"),
					action_group = bind(item, "action-group"):as(function(ag)
						return { "dbusmenu", ag }
					end),
					Widget.Icon({
						gicon = bind(item, "gicon"),
					}),
				})
			end)
		end),
	})
end

local function Media()
	local player = Mpris.Player.new("spotify")

	return Widget.Box({
		class_name = "Media",
		visible = safe_bind(player, "available"),
		Widget.Box({
			class_name = "Cover",
			valign = "CENTER",
			css = safe_bind(player, "cover-art"):as(function(cover)
				return cover and "background-image: url('" .. cover .. "');" or ""
			end),
		}),
		Widget.Label({
			label = safe_bind(player, "metadata"):as(function()
				return string.format("%s - %s", player.title or "", player.artist or "")
			end),
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

local function AudioControl()
	local audio = Wp.get_default().audio
	local speaker = audio and audio.default_speaker
	local mic = audio and audio.default_microphone
	local window_visible = false
	local audio_window = nil

	local function toggle_audio_window()
		if window_visible and audio_window then
			audio_window:hide()
			window_visible = false
		else
			if not audio_window then
				local AudioControlWindow = require("lua.windows.AudioControl")
				audio_window = AudioControlWindow.new()
			end
			audio_window:show_all()
			window_visible = true
		end
	end

	return Widget.Button({
		class_name = "audio-button",
		on_clicked = toggle_audio_window,
		Widget.Box({
			spacing = 10,
			Widget.Icon({
				icon = safe_bind(mic, "volume-icon"),
				tooltip_text = safe_bind(mic, "volume"):as(function(v)
					return string.format("Microphone Volume: %.0f%%", (v or 0) * 100)
				end),
			}),
			Widget.Icon({
				tooltip_text = safe_bind(speaker, "volume"):as(function(v)
					return string.format("Audio Volume: %.0f%%", (v or 0) * 100)
				end),
				icon = safe_bind(speaker, "volume-icon"),
			}),
		}),
	})
end

local function Wifi()
	local network = Network.get_default()
	local wifi = bind(network, "wifi")
	local window_visible = false
	local network_window = nil

	local function toggle_network_window()
		if window_visible and network_window then
			network_window:hide()
			window_visible = false
		else
			if not network_window then
				local NetworkWindow = require("lua.windows.Network")
				network_window = NetworkWindow.new()
			end
			network_window:show_all()
			window_visible = true
		end
	end

	return Widget.Button({
		class_name = "wifi-button",
		visible = wifi:as(function(v)
			return v ~= nil
		end),
		on_clicked = toggle_network_window,
		wifi:as(function(w)
			return Widget.Icon({
				tooltip_text = bind(w, "ssid"):as(tostring),
				class_name = "Wifi",
				icon = bind(w, "icon-name"),
			})
		end),
	})
end

local function BatteryLevel()
	local bat = Battery.get_default()
	local window_visible = false
	local battery_window = nil

	local function toggle_battery_window()
		if window_visible and battery_window then
			battery_window:hide()
			window_visible = false
		else
			if not battery_window then
				local BatteryWindow = require("lua.windows.Battery")
				battery_window = BatteryWindow.new()
			end
			battery_window:show_all()
			window_visible = true
		end
	end

	return Widget.Button({
		class_name = "battery-button",
		visible = bind(bat, "is-present"),
		on_clicked = toggle_battery_window,
		Widget.Box({
			Widget.Icon({
				icon = bind(bat, "battery-icon-name"),
				css = "padding-right: 5pt;",
			}),
			Widget.Label({
				label = bind(bat, "percentage"):as(function(p)
					return tostring(math.floor(p * 100)) .. " %"
				end),
			}),
		}),
	})
end

return function(gdkmonitor)
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
		end,
		Widget.CenterBox({
			Widget.Box({
				halign = "START",
				-- Workspaces(),
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
				AudioControl(),
				Wifi(),
				BatteryLevel(),
			}),
		}),
	})

	return bar
end
