local astal = require("astal")
local Variable = require("astal.variable")
local Debug = require("lua.lib.debug")

local Vitals = {}

function Vitals:New()
	local instance = {
		cpu_usage = Variable(0):poll(1000, function(prev)
			return self:calculate_cpu_usage()
		end),
		memory_usage = Variable(0):poll(1000, function(prev)
			return self:calculate_ram_usage()
		end),
		disk_usage = Variable(0),
		temperature = Variable(0),
	}
	setmetatable(instance, self)
	self.__index = self
	return instance
end

function Vitals:start_monitoring()
	self.cpu_usage:start_poll()
	self.memory_usage:start_poll()
end

function Vitals:stop_monitoring()
	self.cpu_usage:stop_poll()
	self.memory_usage:stop_poll()
end

function Vitals:calculate_cpu_usage()
	local content = astal.read_file("/proc/stat")
	if not content then
		Debug.error("Vitals", "Failed to read /proc/stat")
		return 0
	end

	local cpu_line = content:match("^cpu%s+(%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+)")
	if not cpu_line then
		Debug.error("Vitals", "Failed to parse CPU stats from /proc/stat")
		return 0
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
	return math.floor((used / total) * 100 + 0.5)
end

function Vitals:calculate_ram_usage()
	local content = astal.read_file("/proc/meminfo")
	if not content then
		Debug.error("Vitals", "Failed to read /proc/meminfo")
		return 0
	end

	local total = content:match("MemTotal:%s+(%d+)")
	local free = content:match("MemFree:%s+(%d+)")
	local buffers = content:match("Buffers:%s+(%d+)")
	local cached = content:match("Cached:%s+(%d+)")

	total = tonumber(total)
	free = tonumber(free)
	buffers = tonumber(buffers)
	cached = tonumber(cached)

	if not (total and free and buffers and cached) then
		Debug.error("Vitals", "Failed to parse memory stats from /proc/meminfo")
		return 0
	end

	local used = total - free - buffers - cached
	return math.floor((used / total) * 100 + 0.5)
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
