local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local GLib = astal.require("GLib")
local Network = astal.require("AstalNetwork")
local Debug = require("lua.lib.debug")

local network = Network.get_default()
local wifi = network.wifi

if not network or not wifi then
	Debug.error(
		"Network",
		"Failed to initialize network services - Network: %s, WiFi: %s",
		network and "OK" or "NULL",
		wifi and "OK" or "NULL"
	)
end

local function remove_duplicates(list)
	local seen = {}
	local result = {}
	for _, item in ipairs(list) do
		if item.ssid and not seen[item.ssid] then
			table.insert(result, item)
			seen[item.ssid] = true
		end
	end
	return result
end

local function sort_by_priority(list)
	table.sort(list, function(a, b)
		return (a.strength or 0) > (b.strength or 0)
	end)
end

local function connect_to_access_point(access_point)
	if not access_point or not access_point.ssid then
		Debug.error("Network", "Invalid access point data for connection")
		return
	end
	Debug.info("Network", "Attempting to connect to %s (%s)", access_point.ssid, access_point.bssid)
	astal.exec_async(string.format("nmcli device wifi connect %s", access_point.bssid))
end

local function AirplaneMode(airplane_mode)
	return Widget.Box({
		class_name = "airplane-mode",
		orientation = "HORIZONTAL",
		spacing = 10,
		Widget.Label({
			label = "Airplane Mode",
			xalign = 0,
			hexpand = true,
		}),
		Widget.Switch({
			active = airplane_mode(),
			on_state_set = function(_, state)
				if state then
					wifi.enabled = false
				end
				airplane_mode:set(state)
				return true
			end,
		}),
	})
end

local function WifiToggle(is_enabled)
	local wifi_enabled = Variable.derive({ bind(wifi, "enabled") }, function(enabled)
		return enabled
	end)

	return Widget.Box({
		class_name = "wifi-toggle",
		orientation = "HORIZONTAL",
		spacing = 10,
		Widget.Label({
			label = "Wi-Fi",
			xalign = 0,
			hexpand = true,
		}),
		Widget.Switch({
			active = wifi_enabled(),
			on_state_set = function(_, state)
				wifi.enabled = state
				is_enabled:set(state)
				return true
			end,
		}),
	})
end

local function CurrentNetwork()
	local wifi_ssid = Variable.derive({ bind(wifi, "ssid") }, function(ssid)
		return ssid or "Not Connected"
	end)

	local wifi_strength = Variable.derive({ bind(wifi, "strength") }, function(strength)
		if not strength then
			return "N/A"
		end
		if strength >= 80 then
			return "Excellent"
		end
		if strength >= 60 then
			return "Good"
		end
		if strength >= 40 then
			return "Fair"
		end
		return "Weak"
	end)

	local wifi_frequency = Variable.derive({ bind(wifi, "frequency") }, function(freq)
		return freq and string.format("%.1f GHz", freq / 1000) or "N/A"
	end)

	local wifi_bandwidth = Variable.derive({ bind(wifi, "bandwidth") }, function(bw)
		return bw and string.format("%d Mbps", bw) or "N/A"
	end)

	return Widget.Box({
		class_name = "current-network",
		orientation = "VERTICAL",
		spacing = 5,
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 10,
			Widget.Icon({
				icon = bind(wifi, "icon-name"),
			}),
			Widget.Label({
				label = wifi_ssid(),
				xalign = 0,
			}),
		}),
		Widget.Box({
			class_name = "network-details",
			orientation = "VERTICAL",
			spacing = 5,
			Widget.Box({
				orientation = "HORIZONTAL",
				Widget.Label({ label = "Signal Strength:" }),
				Widget.Label({
					label = wifi_strength(),
					xalign = 1,
					hexpand = true,
				}),
			}),
			Widget.Box({
				orientation = "HORIZONTAL",
				Widget.Label({ label = "Frequency:" }),
				Widget.Label({
					label = wifi_frequency(),
					xalign = 1,
					hexpand = true,
				}),
			}),
			Widget.Box({
				orientation = "HORIZONTAL",
				Widget.Label({ label = "Bandwidth:" }),
				Widget.Label({
					label = wifi_bandwidth(),
					xalign = 1,
					hexpand = true,
				}),
			}),
		}),
	})
end

local function VisibleNetworks(parent)
	local is_scanning = Variable(false)
	local networks_ready = Variable(false)
	local show_networks = Variable(false)
	local cached_networks = Variable({})

	local function start_scan()
		if wifi.enabled then
			Debug.debug("Network", "Starting network scan")
			is_scanning:set(true)
			networks_ready:set(false)
			cached_networks:set({})

			local scan_result = wifi:scan()
			if not scan_result then
				if not wifi or wifi.state == "ERROR" then
					Debug.error(
						"Network",
						"Critical: Failed to initiate network scan - WiFi state: %s",
						tostring(wifi and wifi.state or "unknown")
					)
				end
			end

			GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, function()
				cached_networks:set(wifi.access_points or {})
				if not cached_networks:get() then
					Debug.error("Network", "Failed to get access points after scan")
				end
				is_scanning:set(false)
				networks_ready:set(true)
				return GLib.SOURCE_REMOVE
			end)
		end
	end

	local networks_list = Variable.derive({ networks_ready, cached_networks }, function(ready, networks)
		if not wifi.enabled then
			return {
				Widget.Label({
					label = "Wi-Fi is disabled",
					xalign = 0.5,
				}),
			}
		end

		if not ready then
			return {
				Widget.Label({
					label = "Scanning for networks...",
					xalign = 0.5,
				}),
			}
		end

		local list = {}
		if networks then
			for _, ap in ipairs(networks) do
				if ap and ap.ssid and ap.ssid ~= "" then
					table.insert(list, ap)
				end
			end
		end

		list = remove_duplicates(list)
		sort_by_priority(list)

		if #list == 0 then
			Debug.debug("Network", "No networks found after scan")
			return {
				Widget.Label({
					label = "No networks found",
					xalign = 0.5,
				}),
			}
		end

		local buttons = {}
		for _, item in ipairs(list) do
			local is_active = wifi.active_access_point and wifi.active_access_point.ssid == item.ssid

			table.insert(
				buttons,
				Widget.Button({
					class_name = "network-item" .. (is_active and " active" or ""),
					on_clicked = function()
						connect_to_access_point(item)
					end,
					child = Widget.Box({
						orientation = "HORIZONTAL",
						spacing = 10,
						Widget.Icon({ icon = item.icon_name or "network-wireless-symbolic" }),
						Widget.Label({
							label = item.ssid or "",
							xalign = 0,
							hexpand = true,
						}),
						Widget.Label({
							label = item.strength and string.format("%d%%", item.strength) or "N/A",
							xalign = 1,
						}),
					}),
				})
			)
		end
		return buttons
	end)

	return Widget.Box({
		class_name = "visible-networks",
		orientation = "VERTICAL",
		spacing = 5,
		Widget.Button({
			class_name = "network-selector",
			on_clicked = function()
				show_networks:set(not show_networks:get())
				if show_networks:get() then
					start_scan()
				else
					is_scanning:set(false)
					networks_ready:set(false)
					cached_networks:set({})
				end
			end,
			child = Widget.Box({
				orientation = "HORIZONTAL",
				spacing = 10,
				Widget.Icon({ icon = "network-wireless-symbolic" }),
				Widget.Box({
					hexpand = true,
					Widget.Label({
						label = Variable.derive({ is_scanning }, function(scanning)
							return scanning and "Scanning..." or "Available Networks"
						end)(),
						xalign = 0,
					}),
				}),
				Widget.Icon({
					icon = "pan-down-symbolic",
					class_name = Variable.derive({ show_networks }, function(shown)
						return shown and "expanded" or ""
					end)(),
				}),
			}),
		}),
		Widget.Revealer({
			transition_duration = 200,
			transition_type = "SLIDE_DOWN",
			reveal_child = show_networks(),
			child = Widget.Scrollable({
				vscrollbar_policy = "AUTOMATIC",
				hscrollbar_policy = "NEVER",
				class_name = "network-list",
				child = Widget.Box({
					orientation = "VERTICAL",
					spacing = 5,
					networks_list(),
				}),
			}),
		}),
	})
end

local function Settings(close_window)
	return Widget.Box({
		class_name = "settings",
		Widget.Button({
			label = "Network Settings",
			on_clicked = function()
				if close_window then
					close_window()
				end
				GLib.spawn_command_line_async("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center wifi")
			end,
		}),
	})
end

local NetworkWindow = {}

function NetworkWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Network", "Failed to initialize: gdkmonitor is nil")
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
		class_name = "NetworkWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		setup = function(self)
			local airplane_mode = Variable(false)
			local is_enabled = Variable(wifi and wifi.enabled or false)

			self:add(Widget.Box({
				orientation = "VERTICAL",
				spacing = 15,
				css = "padding: 15px;",
				AirplaneMode(airplane_mode),
				WifiToggle(is_enabled),
				CurrentNetwork(),
				VisibleNetworks(self),
				Settings(close_window),
			}))
		end,
	})

	return window
end

return NetworkWindow
