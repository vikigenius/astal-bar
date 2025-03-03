local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Vitals = require("lua.lib.vitals")

local function CpuWidget()
	local vitals = Vitals.get_default()

	return Widget.Box({
		class_name = "cpu",
		Widget.Icon({
			icon = os.getenv("PWD") .. "/icons/cpu-symbolic.svg",
			css = "padding-right: 5pt;",
		}),
		Widget.Label({
			label = bind(vitals.cpu_usage):as(function(usage)
				return string.format("%d%%", usage)
			end),
		}),
	})
end

local function MemoryWidget()
	local vitals = Vitals.get_default()

	return Widget.Box({
		class_name = "memory",
		Widget.Icon({
			icon = os.getenv("PWD") .. "/icons/memory-symbolic.svg",
			css = "padding-right: 5pt;",
		}),
		Widget.Label({
			label = bind(vitals.memory_usage):as(function(usage)
				return string.format("%d%%", usage)
			end),
		}),
	})
end

local function VitalsWidget()
	return Widget.Box({
		css = "padding: 0 5pt;",
		class_name = "Vitals",
		spacing = 5,
		MemoryWidget(),
		CpuWidget(),
	})
end

return function()
	return VitalsWidget()
end
