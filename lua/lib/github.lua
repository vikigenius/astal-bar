local astal = require("astal")
local cjson = require("cjson")
local GLib = astal.require("GLib")

local CACHE_DIR = GLib.get_user_cache_dir() .. "/astal"
local CACHE_FILE = CACHE_DIR .. "/github-events.json"
local CACHE_EXPIRY = 5 * 60
local POLL_INTERVAL = 300000

local Github = {
	get_events = nil,
	format_time = nil,
	CACHE_EXPIRY = CACHE_EXPIRY,
	POLL_INTERVAL = POLL_INTERVAL,
}

local config_path = debug.getinfo(1).source:match("@?(.*/)") .. "../../user-variables.lua"
local user_vars = loadfile(config_path)()

local function ensure_cache_dir()
	if not GLib.file_test(CACHE_DIR, "EXISTS") then
		GLib.mkdir_with_parents(CACHE_DIR, 0755)
	end
end

local function load_cache()
	if not GLib.file_test(CACHE_FILE, "EXISTS") then
		return nil
	end

	local content = astal.read_file(CACHE_FILE)
	if not content then
		return nil
	end

	local success, cache = pcall(cjson.decode, content)
	if not success then
		if GLib.file_test(CACHE_FILE, "EXISTS") then
			os.remove(CACHE_FILE)
		end
		return nil
	end

	if os.time() - (cache.timestamp or 0) > CACHE_EXPIRY then
		if GLib.file_test(CACHE_FILE, "EXISTS") then
			os.remove(CACHE_FILE)
		end
		return nil
	end

	return cache.events
end

local function save_cache(events)
	ensure_cache_dir()

	local cache = {
		timestamp = os.time(),
		events = events,
	}

	local success, encoded = pcall(cjson.encode, cache)
	if not success then
		return false
	end

	if not GLib.file_test(CACHE_FILE, "EXISTS") then
		astal.write_file(CACHE_FILE, "")
	end

	return astal.write_file(CACHE_FILE, encoded)
end

local function fetch_github_events(username)
	local url = string.format("https://api.github.com/users/%s/received_events", username)
	local output, err = astal.exec({ "curl", "-s", "-H", "Accept: application/vnd.github+json", url })

	if err or not output then
		return nil
	end

	local success, events = pcall(cjson.decode, output)
	if not success then
		return nil
	end

	return events
end

local function filter_events(events)
	if not events then
		return {}
	end

	local filtered = {}
	for _, event in ipairs(events) do
		if
			not event.type:match("^GitHub")
			and event.actor.login ~= "github-actions[bot]"
			and not event.actor.login:match("^bot")
			and not event.actor.login:match("%[bot%]$")
		then
			table.insert(filtered, event)
		end
	end
	return filtered
end

function Github.get_events()
	ensure_cache_dir()

	local cached_events = load_cache()
	if cached_events then
		return filter_events(cached_events)
	end

	local username = user_vars.github and user_vars.github.username or "linuxmobile"
	local events = fetch_github_events(username)

	if events then
		save_cache(events)
		return filter_events(events)
	end

	return {}
end

function Github.format_time(iso_time)
	local timestamp = GLib.DateTime.new_from_iso8601(iso_time, nil)
	local now = GLib.DateTime.new_now_local()
	local diff = now:difference(timestamp) / 1000000

	if diff < 60 then
		return "just now"
	elseif diff < 3600 then
		return string.format("%d minutes ago", math.floor(diff / 60))
	elseif diff < 86400 then
		return string.format("%d hours ago", math.floor(diff / 3600))
	else
		return string.format("%d days ago", math.floor(diff / 86400))
	end
end

return Github
