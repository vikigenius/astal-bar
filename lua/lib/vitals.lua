local astal = require("astal")
local Variable = require("astal.variable")
local Debug = require("lua.lib.debug")
local Managers = require("lua.lib.managers")

local Vitals = {}

function Vitals:New()
	local instance = {
		cpu_usage = Variable(0),
		memory_usage = Variable(0),
		disk_usage = Variable(0),
		temperature = Variable(0),
	}

	Managers.VariableManager.register(instance.cpu_usage)
	Managers.VariableManager.register(instance.memory_usage)
	Managers.VariableManager.register(instance.disk_usage)
	Managers.VariableManager.register(instance.temperature)

	setmetatable(instance, self)
	self.__index = self
	return instance
end

local function file_exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end
	return false
end

function Vitals:start_monitoring()
	if not file_exists("/proc/stat") then
		Debug.error("Vitals", "Cannot monitor CPU: /proc/stat not accessible")
		return
	end
	if not file_exists("/proc/meminfo") then
		Debug.error("Vitals", "Cannot monitor RAM: /proc/meminfo not accessible")
		return
	end

	self._cpu_timer = astal.interval(1000, function()
		self:update_cpu_usage()
	end)

	self._ram_timer = astal.interval(1000, function()
		self:update_ram_usage()
	end)
end

function Vitals:stop_monitoring()
	if self._cpu_timer then
		self._cpu_timer:cancel()
	end
	if self._ram_timer then
		self._ram_timer:cancel()
	end

	if self.cpu_usage then
		Managers.VariableManager.cleanup(self.cpu_usage)
	end
	if self.memory_usage then
		Managers.VariableManager.cleanup(self.memory_usage)
	end
	if self.disk_usage then
		Managers.VariableManager.cleanup(self.disk_usage)
	end
	if self.temperature then
		Managers.VariableManager.cleanup(self.temperature)
	end
end

function Vitals:update_cpu_usage()
	local content = astal.read_file("/proc/stat")
	if not content then
		Debug.error("Vitals", "Failed to read CPU stats")
		return
	end

	local cpu_line = content:match("^cpu%s+(%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+)")
	if not cpu_line then
		Debug.error("Vitals", "Invalid CPU stats format")
		return
	end

	local values = {}
	for v in cpu_line:gmatch("%d+") do
		table.insert(values, tonumber(v))
	end

	local user = values[1]
	local nice = values[2]
	local system = values[3]
	local idle = values[4]
	local iowait = values[5]

	local total = user + nice + system + idle + iowait
	local used = total - (idle + iowait)
	self.cpu_usage:set(math.floor((used / total) * 100 + 0.5))
end

function Vitals:update_ram_usage()
	local content = astal.read_file("/proc/meminfo")
	if not content then
		Debug.error("Vitals", "Failed to read memory stats")
		return
	end

	local total = content:match("MemTotal:%s+(%d+)")
	local free = content:match("MemFree:%s+(%d+)")
	local buffers = content:match("Buffers:%s+(%d+)")
	local cached = content:match("Cached:%s+(%d+)")

	if not (total and free and buffers and cached) then
		Debug.error("Vitals", "Invalid memory stats format")
		return
	end

	total = tonumber(total)
	free = tonumber(free)
	buffers = tonumber(buffers)
	cached = tonumber(cached)

	local used = total - free - buffers - cached
	self.memory_usage:set(math.floor((used / total) * 100 + 0.5))
end

local instance = nil
function Vitals.get_default()
	if not instance then
		instance = Vitals:New()
		instance:start_monitoring()
	end
	return instance
end

return Vitals
