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

local Workspaces = require("lua.widgets.Workspaces")
local ActiveClient = require("lua.widgets.ActiveClient")
local Vitals = require("lua.widgets.Vitals")

local map = require("lua.lib.common").map

local github_window = nil
local audio_window = nil
local network_window = nil
local battery_window = nil

local function SysTray()
	local tray = Tray.get_default()
	return Widget.Box({
		class_name = "SysTray",
		bind(tray, "items"):as(function(items)
			return map(items or {}, function(item)
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
	local player = Mpris.Player.new("zen")
	local player_available = Variable.derive({ bind(player, "available") }, function(available)
		return available
	end)

	local player_metadata = Variable.derive({ bind(player, "metadata") }, function()
		return string.format("%s - %s", player.title or "", player.artist or "")
	end)

	return Widget.Box({
		class_name = "Media",
		visible = bind(player_available),
		Widget.Box({
			class_name = "Cover",
			valign = "CENTER",
			css = bind(player, "cover-art"):as(function(cover)
				return cover and "background-image: url('" .. cover .. "');" or ""
			end),
		}),
		Widget.Label({
			label = bind(player_metadata),
		}),
		setup = function(self)
			self:hook(self, "destroy", function()
				player_available:drop()
				player_metadata:drop()
			end)
		end,
	})
end

local function Time(format)
	local time = Variable(""):poll(1000, function()
		local success, datetime = pcall(function()
			return GLib.DateTime.new_now_local():format(format)
		end)
		return success and datetime or ""
	end)

	return Widget.Label({
		class_name = "Time",
		label = bind(time),
		setup = function(self)
			self:hook(self, "destroy", function()
				time:drop()
			end)
		end,
	})
end

local function GithubActivity()
	local window_visible = Variable(false)

	local function toggle_github_window()
		if window_visible:get() and github_window then
			github_window:hide()
			window_visible:set(false)
		else
			if not github_window then
				local GithubWindow = require("lua.windows.Github")
				github_window = GithubWindow.new()
			end
			github_window:show_all()
			window_visible:set(true)
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
	local window_visible = Variable(false)

	local function toggle_audio_window()
		if window_visible:get() and audio_window then
			audio_window:hide()
			window_visible:set(false)
		else
			if not audio_window then
				local AudioControlWindow = require("lua.windows.AudioControl")
				audio_window = AudioControlWindow.new(monitor)
			end
			if audio_window then
				audio_window:show_all()
			end
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "audio-button",
		on_clicked = toggle_audio_window,
		Widget.Box({
			spacing = 10,
			Widget.Icon({
				icon = bind(mic, "volume-icon"),
				tooltip_text = bind(mic, "volume"):as(function(v)
					return string.format("Microphone Volume: %.0f%%", (v or 0) * 100)
				end),
			}),
			Widget.Icon({
				tooltip_text = bind(speaker, "volume"):as(function(v)
					return string.format("Audio Volume: %.0f%%", (v or 0) * 100)
				end),
				icon = bind(speaker, "volume-icon"),
			}),
		}),
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
			end)
		end,
	})
end

local function Wifi(monitor)
	local network = Network.get_default()
	local window_visible = Variable(false)
	local wifi_state = Variable.derive({ bind(network, "wifi") }, function(wifi)
		return wifi
	end)

	local function toggle_network_window()
		if window_visible:get() and network_window then
			network_window:hide()
			window_visible:set(false)
		else
			if not network_window then
				local NetworkWindow = require("lua.windows.Network")
				network_window = NetworkWindow.new(monitor)
			end
			if network_window then
				network_window:show_all()
			end
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "wifi-button",
		visible = bind(wifi_state):as(function(v)
			return v ~= nil
		end),
		on_clicked = toggle_network_window,
		bind(wifi_state):as(function(w)
			return Widget.Icon({
				tooltip_text = bind(w, "ssid"):as(tostring),
				class_name = "Wifi",
				icon = bind(w, "icon-name"),
			})
		end),
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
				wifi_state:drop()
			end)
		end,
	})
end

local function BatteryLevel(monitor)
	local bat = Battery.get_default()
	local window_visible = Variable(false)
	local battery_state = Variable.derive({ bind(bat, "is-present") }, function(present)
		return present
	end)

	local function toggle_battery_window()
		if window_visible:get() and battery_window then
			battery_window:hide()
			window_visible:set(false)
		else
			if not battery_window then
				local BatteryWindow = require("lua.windows.Battery")
				battery_window = BatteryWindow.new(monitor)
			end
			if battery_window then
				battery_window:show_all()
			end
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "battery-button",
		visible = bind(battery_state),
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
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
				battery_state:drop()
			end)
		end,
	})
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Bar", "No monitor available")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor

	return Widget.Window({
		class_name = "Bar",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.LEFT + Anchor.RIGHT,
		exclusivity = "EXCLUSIVE",
		on_destroy = function()
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
				AudioControl(gdkmonitor),
				Wifi(gdkmonitor),
				BatteryLevel(gdkmonitor),
			}),
		}),
	})
end
