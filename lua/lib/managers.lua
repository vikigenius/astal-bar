local Debug = require("lua.lib.debug")

local VariableManager, BindingManager

VariableManager = {
	_variables = {},
	_count = 0,

	register = function(var, cleanup_cb)
		if not var then
			Debug.error("VariableManager", "Attempted to register nil variable")
			return nil
		end

		local id = VariableManager._count + 1
		VariableManager._count = id
		VariableManager._variables[id] = {
			var = var,
			cleanup = cleanup_cb,
		}
		return id
	end,

	cleanup = function(id)
		local entry = VariableManager._variables[id]
		if not entry then
			Debug.warn("VariableManager", "Attempted to clean up non-existent variable #%d", id)
			return
		end

		if entry.cleanup then
			entry.cleanup()
		end

		if entry.var and entry.var.drop then
			entry.var:drop()
		end

		VariableManager._variables[id] = nil
	end,

	cleanup_all = function()
		for id, _ in pairs(VariableManager._variables) do
			VariableManager.cleanup(id)
		end
		Debug.debug("VariableManager", "Cleaned up all variables (%d total)", VariableManager._count)
	end,

	get_stats = function()
		local count = 0
		for _ in pairs(VariableManager._variables) do
			count = count + 1
		end
		return {
			total_registered = VariableManager._count,
			active = count,
		}
	end,
}

BindingManager = {
	_bindings = {},
	_count = 0,

	register = function(binding, cleanup_cb)
		if not binding then
			Debug.error("BindingManager", "Attempted to register nil binding")
			return nil
		end

		local id = BindingManager._count + 1
		BindingManager._count = id
		BindingManager._bindings[id] = {
			binding = binding,
			cleanup = cleanup_cb,
		}
		return id
	end,

	cleanup = function(id)
		local entry = BindingManager._bindings[id]
		if not entry then
			Debug.warn("BindingManager", "Attempted to clean up non-existent binding #%d", id)
			return
		end

		if entry.cleanup then
			entry.cleanup()
		end

		BindingManager._bindings[id] = nil
	end,

	cleanup_all = function()
		for id, _ in pairs(BindingManager._bindings) do
			BindingManager.cleanup(id)
		end
		Debug.debug("BindingManager", "Cleaned up all bindings (%d total)", BindingManager._count)
	end,

	get_stats = function()
		local count = 0
		for _ in pairs(BindingManager._bindings) do
			count = count + 1
		end
		return {
			total_registered = BindingManager._count,
			active = count,
		}
	end,
}

return {
	VariableManager = VariableManager,
	BindingManager = BindingManager,
}
