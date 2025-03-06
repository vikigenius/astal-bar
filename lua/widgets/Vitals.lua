local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Vitals = require("lua.lib.vitals")
local Managers = require("lua.lib.managers")

local function CpuWidget()
	local vitals = Vitals.get_default()
	Managers.VariableManager.register(vitals)

	local cpu_usage_binding = bind(vitals.cpu_usage)
	Managers.BindingManager.register(cpu_usage_binding)

	return Widget.Box({
		class_name = "cpu",
		Widget.Icon({
			icon = os.getenv("PWD") .. "/icons/cpu-symbolic.svg",
			css = "padding-right: 5pt;",
		}),
		Widget.Label({
			label = cpu_usage_binding:as(function(usage)
				return string.format("%d%%", usage)
			end),
		}),
	})
end

local function MemoryWidget()
	local vitals = Vitals.get_default()
	Managers.VariableManager.register(vitals)

	local memory_usage_binding = bind(vitals.memory_usage)
	Managers.BindingManager.register(memory_usage_binding)

	return Widget.Box({
		class_name = "memory",
		Widget.Icon({
			icon = os.getenv("PWD") .. "/icons/memory-symbolic.svg",
			css = "padding-right: 5pt;",
		}),
		Widget.Label({
			label = memory_usage_binding:as(function(usage)
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
		on_destroy = function()
			Managers.BindingManager.cleanup_all()
			Managers.VariableManager.cleanup_all()
		end,
	})
end

return function()
	return VitalsWidget()
end
