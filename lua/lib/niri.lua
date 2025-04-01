local astal = require("astal")
local cjson = require("cjson")
local GLib = require("lgi").GLib
local Gio = require("lgi").Gio
local Debug = require("lua.lib.debug")
local Variable = astal.Variable

local DEFAULT_CONFIG = {
	monitor_order = { "eDP-1", "HDMI-A-1" },
	monitor_poll_interval = 5000,
	workspace_poll_interval = 250,
	window_poll_interval = 450,
	window_debounce_threshold = 100000,
}

local cache = {
	monitors = { timestamp = 0, data = {}, max_age = 5 },
	workspaces = { hash = "", data = {}, max_entries = 50 },
	windows = { data = {}, timestamp = 0 },
}

local rate_limiter = {
	last_monitor_fetch = 0,
	last_workspace_fetch = 0,
	last_window_fetch = 0,
}

local function exec_niri_cmd(cmd)
	local full_cmd = "niri msg --json " .. cmd
	local out, err = astal.exec(full_cmd)
	if err then
		Debug.error("Niri", "Failed to execute niri command: %s, error: %s", full_cmd, err)
		return nil, err
	end

	local success, data = pcall(cjson.decode, out)
	if not success then
		Debug.error("Niri", "Failed to decode JSON from niri command: %s", cmd)
		return nil, "JSON decode error"
	end

	return data
end

local function get_monitors(config)
	config = config or DEFAULT_CONFIG
	local monitor_order = config.monitor_order or DEFAULT_CONFIG.monitor_order
	local current_time = GLib.get_monotonic_time() / 1000000

	if current_time - cache.monitors.timestamp < cache.monitors.max_age then
		return cache.monitors.data
	end

	if
		current_time - rate_limiter.last_monitor_fetch
		< ((config.monitor_poll_interval or DEFAULT_CONFIG.monitor_poll_interval) / 1000)
	then
		return cache.monitors.data
	end

	rate_limiter.last_monitor_fetch = current_time

	local monitors = exec_niri_cmd("outputs")
	if not monitors then
		return {}
	end

	local monitor_array = {}
	for _, name in ipairs(monitor_order) do
		if monitors[name] then
			table.insert(monitor_array, {
				name = name,
				id = name:gsub("-", "_"),
				logical = monitors[name].logical,
			})
		end
	end

	cache.monitors.timestamp = current_time
	cache.monitors.data = monitor_array

	return monitor_array
end

local function process_workspaces(config)
	config = config or DEFAULT_CONFIG
	local current_time = GLib.get_monotonic_time() / 1000000

	if
		current_time - rate_limiter.last_workspace_fetch
		< ((config.workspace_poll_interval or DEFAULT_CONFIG.workspace_poll_interval) / 1000)
	then
		return cache.workspaces.data
	end

	rate_limiter.last_workspace_fetch = current_time

	local workspaces = exec_niri_cmd("workspaces")
	if not workspaces then
		return cache.workspaces.data
	end

	local state_hash = ""
	for i, w in ipairs(workspaces) do
		state_hash = state_hash .. w.output .. "-" .. w.idx .. "-" .. (w.is_active and "1" or "0")
		if i < #workspaces then
			state_hash = state_hash .. "|"
		end
	end

	if cache.workspaces.hash == state_hash then
		return cache.workspaces.data
	end

	local monitors = get_monitors(config)
	local output_workspaces = {}

	for _, workspace in ipairs(workspaces) do
		output_workspaces[workspace.output] = output_workspaces[workspace.output] or {}
		table.insert(output_workspaces[workspace.output], {
			id = workspace.idx,
			is_active = workspace.is_active,
			workspace_id = workspace.id,
		})
	end

	local workspace_data = {}
	for _, monitor in ipairs(monitors) do
		local monitor_workspaces = output_workspaces[monitor.name] or {}
		table.sort(monitor_workspaces, function(a, b)
			return a.id < b.id
		end)
		table.insert(workspace_data, {
			monitor = monitor.id,
			name = monitor.name,
			workspaces = monitor_workspaces,
		})
	end

	cache.workspaces.hash = state_hash
	cache.workspaces.data = workspace_data

	return workspace_data
end

local function get_active_window(config)
	config = config or DEFAULT_CONFIG
	local current_time = GLib.get_monotonic_time()
	local threshold = config.window_debounce_threshold or DEFAULT_CONFIG.window_debounce_threshold

	if (current_time - cache.windows.timestamp) < threshold then
		return cache.windows.data
	end

	local windows = exec_niri_cmd("windows")
	if not windows then
		return cache.windows.data
	end

	for _, window in ipairs(windows) do
		if window.is_focused then
			cache.windows.data = window
			cache.windows.timestamp = current_time
			return window
		end
	end

	cache.windows.data = {}
	cache.windows.timestamp = current_time
	return cache.windows.data
end

local function get_all_windows()
	local windows = exec_niri_cmd("windows")
	return windows or {}
end

local function switch_to_workspace(workspace_index, monitor_name)
	local cmd = string.format("niri msg action switch-to-workspace-index %d %s", workspace_index - 1, monitor_name)
	local _, err = astal.exec(cmd)
	if err then
		Debug.error("Niri", "Failed to switch workspace: %s", err)
		return false
	end
	return true
end

local function create_workspace_variables(config)
	config = config or DEFAULT_CONFIG
	local is_destroyed = false

	local workspace_data = Variable(process_workspaces(config))
	local monitors_var = Variable(get_monitors(config))

	local workspaces = Variable.derive({ workspace_data, monitors_var }, function(ws_data, monitors)
		if is_destroyed then
			return {}
		end
		return (ws_data and monitors) and ws_data or {}
	end)

	local workspace_source = Gio.Cancellable()
	workspace_data:poll(config.workspace_poll_interval or DEFAULT_CONFIG.workspace_poll_interval, function()
		if is_destroyed or workspace_source:is_cancelled() then
			return nil
		end
		return process_workspaces(config)
	end)

	local monitor_source = Gio.Cancellable()
	monitors_var:poll(config.monitor_poll_interval or DEFAULT_CONFIG.monitor_poll_interval, function()
		if is_destroyed or monitor_source:is_cancelled() then
			return nil
		end
		return get_monitors(config)
	end)

	return {
		workspace_data = workspace_data,
		monitors_var = monitors_var,
		workspaces = workspaces,
		workspace_source = workspace_source,
		monitor_source = monitor_source,
		cleanup = function()
			is_destroyed = true
			if workspace_source and workspace_source.cancel then
				workspace_source:cancel()
			end
			if monitor_source and monitor_source.cancel then
				monitor_source:cancel()
			end
			workspace_data:drop()
			monitors_var:drop()
			workspaces:drop()
			cache.monitors.data = {}
			cache.workspaces.data = {}
		end,
	}
end

local function create_window_variable(config)
	config = config or DEFAULT_CONFIG
	local var = Variable({})
	local source_id
	local is_cleaned_up = false

	local function poll_callback()
		if is_cleaned_up then
			return GLib.SOURCE_REMOVE
		end
		var:set(get_active_window(config))
		return GLib.SOURCE_CONTINUE
	end

	source_id = GLib.timeout_add(
		GLib.PRIORITY_DEFAULT,
		config.window_poll_interval or DEFAULT_CONFIG.window_poll_interval,
		poll_callback
	)

	local function cleanup()
		is_cleaned_up = true
		if source_id then
			GLib.source_remove(source_id)
			source_id = nil
		end
		var:drop()
		cache.windows.data = {}
		cache.windows.timestamp = 0
	end

	return var, source_id, cleanup
end

local function reset_caches()
	for k in pairs(cache.monitors.data) do
		cache.monitors.data[k] = nil
	end
	cache.monitors.timestamp = 0
	for k in pairs(cache.workspaces.data) do
		cache.workspaces.data[k] = nil
	end
	cache.workspaces.hash = ""
	for k in pairs(cache.windows.data) do
		cache.windows.data[k] = nil
	end
	cache.windows.timestamp = 0
end

return {
	get_monitors = get_monitors,
	get_workspaces = process_workspaces,
	get_active_window = get_active_window,
	get_all_windows = get_all_windows,
	switch_to_workspace = switch_to_workspace,
	create_workspace_variables = create_workspace_variables,
	create_window_variable = create_window_variable,
	reset_caches = reset_caches,
	exec_cmd = exec_niri_cmd,
	DEFAULT_CONFIG = DEFAULT_CONFIG,
}
