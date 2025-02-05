local astal = require("astal")
local Variable = require("astal.variable")

local Vitals = {}

function Vitals:New()
  local instance = {
    cpu_usage = Variable(0),
    memory_usage = Variable(0),
    disk_usage = Variable(0),
    temperature = Variable(0),
  }
  setmetatable(instance, self)
  self.__index = self
  return instance
end

function Vitals:start_monitoring()
  self._cpu_timer = astal.interval(1000, function()
    self:update_cpu_usage()
  end)

  self._ram_timer = astal.interval(1000, function()
    self:update_ram_usage()
  end)
end

function Vitals:stop_monitoring()
  if self._cpu_timer then self._cpu_timer:cancel() end
  if self._ram_timer then self._ram_timer:cancel() end
end

function Vitals:update_cpu_usage()
  local content = astal.read_file("/proc/stat")
  if not content then return end

  local cpu_line = content:match("^cpu%s+(%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+)")
  if not cpu_line then return end

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
  if not content then return end

  local total = content:match("MemTotal:%s+(%d+)")
  local free = content:match("MemFree:%s+(%d+)")
  local buffers = content:match("Buffers:%s+(%d+)")
  local cached = content:match("Cached:%s+(%d+)")

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
