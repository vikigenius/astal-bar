local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local map = require("lua.lib.common").map
local cjson = require("cjson")
local Debug = require("lua.lib.debug")

local monitor_order = { "eDP-1", "HDMI-A-1" }
local monitor_cache = { timestamp = 0, data = {} }

local function get_niri_monitors()
	if os.time() - monitor_cache.timestamp < 5 then
		return monitor_cache.data
	end

	local out, err = astal.exec("niri msg --json outputs")
	if err then
		Debug.error("Workspaces", "Failed to get niri monitors: %s", err)
		return {}
	end

	local success, monitors = pcall(cjson.decode, out)
	if not success then
		Debug.error("Workspaces", "Failed to decode niri monitor data")
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

	monitor_cache.timestamp = os.time()
	monitor_cache.data = monitor_array
	return monitor_array
end

local workspace_cache = { hash = "", data = {} }
local function process_workspace_data()
	local out, err = astal.exec("niri msg --json workspaces")
	if err then
		Debug.error("Workspaces", "Failed to get workspace data: %s", err)
		return workspace_cache.data
	end

	local success, workspaces = pcall(cjson.decode, out)
	if not success then
		Debug.error("Workspaces", "Failed to decode workspace data")
		return workspace_cache.data
	end

	local state_hash = table.concat(
		map(workspaces, function(w)
			return string.format("%s-%d-%s", w.output, w.idx, w.is_active and "1" or "0")
		end),
		"|"
	)

	if workspace_cache.hash == state_hash then
		return workspace_cache.data
	end

	local monitors = get_niri_monitors()
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

	workspace_cache.hash = state_hash
	workspace_cache.data = workspace_data
	return workspace_data
end

local function WorkspaceButton(props)
	return Widget.Button({
		class_name = "workspace-button" .. (props.is_active and " active" or ""),
		on_clicked = function()
			local _, err = astal.exec(
				string.format("niri msg action switch-to-workspace-index %d %s", props.id - 1, props.monitor_name)
			)
			if err then
				Debug.error("Workspaces", "Failed to switch workspace: %s", err)
			end
		end,
	})
end

local function MonitorWorkspaces(props)
	local monitor_number = props.name == "HDMI-A-1" and 2 or 1
	return Widget.Box({
		class_name = string.format("monitor-workspaces monitor-%d", monitor_number),
		orientation = "HORIZONTAL",
		spacing = 3,
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 3,
			table.unpack(map(props.workspaces, function(ws)
				return WorkspaceButton({
					id = ws.id,
					monitor = monitor_number,
					monitor_name = props.name,
					is_active = ws.is_active,
					workspace_id = ws.workspace_id,
				})
			end)),
		}),
	})
end

local function create_workspace_variables()
	local workspace_data = Variable(process_workspace_data())
	local monitors_var = Variable(get_niri_monitors())

	local workspaces = Variable.derive({ workspace_data, monitors_var }, function(ws_data, monitors)
		return (ws_data and monitors) and ws_data or {}
	end)

	workspace_data:poll(250, function()
		local data = process_workspace_data()
		workspace_data:set(data)
		return data
	end)

	monitors_var:poll(5000, function()
		local monitors = get_niri_monitors()
		monitors_var:set(monitors)
		return monitors
	end)

	return workspace_data, monitors_var, workspaces
end

return function()
	local workspace_data, monitors_var, workspaces = create_workspace_variables()

	return Widget.Box({
		class_name = "Workspaces",
		orientation = "HORIZONTAL",
		spacing = 2,
		bind(workspaces):as(function(ws)
			return map(ws, function(monitor)
				return MonitorWorkspaces({
					monitor = monitor.monitor,
					name = monitor.name,
					workspaces = monitor.workspaces,
				})
			end)
		end),
		on_destroy = function()
			workspace_data:drop()
			monitors_var:drop()
			workspaces:drop()
		end,
	})
end
