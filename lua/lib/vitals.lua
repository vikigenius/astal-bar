local astal = require("astal")
local Variable = require("astal.variable")
local Debug = require("lua.lib.debug")

local Vitals = {}

local function parse_cpu_stats(content)
	if not content then
		return nil
	end
	local cpu_line = content:match("^cpu%s+(%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+)")
	if not cpu_line then
		return nil
	end

	local values = {}
	for v in cpu_line:gmatch("%d+") do
		values[#values + 1] = tonumber(v)
	end
	return values
end

local function parse_mem_stats(content)
	if not content then
		return nil
	end

	local stats = {}
	stats.total = tonumber(content:match("MemTotal:%s+(%d+)"))
	stats.free = tonumber(content:match("MemFree:%s+(%d+)"))
	stats.buffers = tonumber(content:match("Buffers:%s+(%d+)"))
	stats.cached = tonumber(content:match("Cached:%s+(%d+)"))

	if not (stats.total and stats.free and stats.buffers and stats.cached) then
		return nil
	end
	return stats
end

function Vitals:calculate_cpu_usage()
	local content = astal.read_file("/proc/stat")
	if not content then
		Debug.error("Vitals", "Failed to read /proc/stat")
		return 0
	end

	local values = parse_cpu_stats(content)
	if not values then
		Debug.error("Vitals", "Failed to parse CPU stats from /proc/stat")
		return 0
	end

	local total = values[1] + values[2] + values[3] + values[4] + values[5]
	local used = total - (values[4] + values[5])
	return math.floor((used / total) * 100 + 0.5)
end

function Vitals:calculate_ram_usage()
	local content = astal.read_file("/proc/meminfo")
	if not content then
		Debug.error("Vitals", "Failed to read /proc/meminfo")
		return 0
	end

	local stats = parse_mem_stats(content)
	if not stats then
		Debug.error("Vitals", "Failed to parse memory stats from /proc/meminfo")
		return 0
	end

	local used = stats.total - stats.free - stats.buffers - stats.cached
	return math.floor((used / stats.total) * 100 + 0.5)
end

function Vitals:New()
	local instance = {
		cpu_usage = Variable(0):poll(1000, function()
			return self:calculate_cpu_usage()
		end),
		memory_usage = Variable(0):poll(1000, function()
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

local instance

function Vitals.get_default()
	if not instance then
		instance = Vitals:New()
		instance:start_monitoring()
	end
	return instance
end

return Vitals
