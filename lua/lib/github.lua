local astal = require("astal")
local cjson = require("cjson")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")

local CACHE_DIR = GLib.get_user_cache_dir() .. "/astal"
local CACHE_FILE = CACHE_DIR .. "/github-events.json"
local CACHE_MIN_LIFETIME = 60
local CACHE_MAX_LIFETIME = 300
local POLL_INTERVAL = 300000
local MAX_RETRIES = 3
local RETRY_DELAY = 10
local RATE_CHECK_INTERVAL = 900
local RATE_LIMIT_COOLDOWN = 3600

local state = {
	last_rate_check = 0,
	last_rate_status = true,
	last_rate_remaining = 60,
	last_rate_error_time = 0,
}

local Github = {
	POLL_INTERVAL = POLL_INTERVAL,
}

local config_path = debug.getinfo(1).source:match("@?(.*/)") .. "../../user-variables.lua"
local user_vars = loadfile(config_path)()

local function ensure_cache_dir()
	if not GLib.file_test(CACHE_DIR, "EXISTS") then
		GLib.mkdir_with_parents(CACHE_DIR, 0755)
	end
end

local function execute_curl(cmd)
	local handle = io.popen(cmd)
	if not handle then
		return nil
	end
	local result = handle:read("*a")
	handle:close()
	return result
end

local function load_cache()
	Debug.debug("GitHub", "Attempting to load cache")
	if not GLib.file_test(CACHE_FILE, "EXISTS") then
		return nil
	end

	local content = astal.read_file(CACHE_FILE)
	if not content then
		return nil
	end

	local success, cache = pcall(cjson.decode, content)
	if not success or type(cache) ~= "table" then
		return nil
	end

	local age = os.time() - (cache.timestamp or 0)
	if age < CACHE_MIN_LIFETIME then
		Debug.debug("GitHub", "Cache is fresh (age: %d seconds)", age)
		return cache.events, false
	elseif age > CACHE_MAX_LIFETIME then
		Debug.debug("GitHub", "Cache is expired (age: %d seconds)", age)
		return cache.events, true
	end
	return cache.events, false
end

local function save_cache(events)
	if not events or type(events) ~= "table" then
		return false
	end
	ensure_cache_dir()

	local cache = { timestamp = os.time(), events = events }
	local success, encoded = pcall(cjson.encode, cache)
	if not success then
		return false
	end

	local temp_file = CACHE_FILE .. ".tmp"
	if not pcall(function()
		astal.write_file(temp_file, encoded)
	end) then
		pcall(os.remove, temp_file)
		return false
	end

	if not pcall(function()
		os.rename(temp_file, CACHE_FILE)
	end) then
		pcall(os.remove, temp_file)
		return false
	end
	return true
end

local function check_rate_limit()
	local current_time = os.time()

	if current_time - state.last_rate_error_time < RATE_LIMIT_COOLDOWN then
		Debug.debug("GitHub", "In rate limit cooldown period")
		return false
	end

	if current_time - state.last_rate_check < RATE_CHECK_INTERVAL then
		Debug.debug("GitHub", "Using cached rate limit status (remaining: %d)", state.last_rate_remaining)
		return state.last_rate_status
	end

	local rate_limit_check = execute_curl(table.concat({
		"curl -s --connect-timeout 3 --max-time 5",
		"https://api.github.com/rate_limit",
		"-H 'Accept: application/vnd.github+json'",
	}, " "))

	if not rate_limit_check then
		Debug.warn("GitHub", "Rate limit check failed")
		state.last_rate_error_time = current_time
		return false
	end

	local success, rate_data = pcall(cjson.decode, rate_limit_check)
	if not success or not rate_data or not rate_data.resources or not rate_data.resources.core then
		Debug.warn("GitHub", "Invalid rate limit response")
		state.last_rate_error_time = current_time
		return false
	end

	local remaining = rate_data.resources.core.remaining
	state.last_rate_remaining = remaining
	state.last_rate_check = current_time

	if remaining < 10 then
		Debug.warn("GitHub", "Rate limit low")
		state.last_rate_error_time = current_time
		state.last_rate_status = false
		return false
	end

	state.last_rate_status = true
	return true
end

local function fetch_github_events(username, attempt)
	attempt = attempt or 1
	if attempt > MAX_RETRIES then
		Debug.warn("GitHub", "Max retries reached")
		return nil, "max_retries"
	end

	if not check_rate_limit() then
		Debug.warn("GitHub", "Rate limit exceeded")
		return nil, "rate_limit"
	end

	local url = string.format("https://api.github.com/users/%s/received_events", username)
	local output = execute_curl(table.concat({
		"curl -s -S --connect-timeout 3 --max-time 5 --compressed",
		"-H 'Accept: application/json'",
		"-H 'Accept-Encoding: gzip, deflate, br'",
		"-H 'User-Agent: astal-bar'",
		"-H 'Connection: keep-alive'",
		"'" .. url .. "'",
	}, " "))

	if not output then
		if attempt < MAX_RETRIES then
			astal.sleep(RETRY_DELAY * (2 ^ (attempt - 1)))
			return fetch_github_events(username, attempt + 1)
		end
		return nil, "network_error"
	end

	local success, events = pcall(cjson.decode, output)
	if not success or type(events) ~= "table" then
		Debug.error("GitHub", "Parse error: %s", success and "invalid format" or events)
		return nil, "parse_error"
	end

	return events
end

function Github.get_events()
	local cached_events, is_expired = load_cache()
	if cached_events and not is_expired then
		return cached_events
	end

	if os.time() - state.last_rate_error_time < RATE_LIMIT_COOLDOWN then
		return cached_events or {}
	end

	local username = user_vars.github and user_vars.github.username or "linuxmobile"
	local events = fetch_github_events(username)

	if events and #events > 0 then
		save_cache(events)
		return events
	end

	return cached_events or {}
end

function Github.format_time(iso_time)
	if not iso_time then
		return "unknown time"
	end

	local timestamp = GLib.DateTime.new_from_iso8601(iso_time, nil)
	if not timestamp then
		return "invalid time"
	end

	local diff = GLib.DateTime.new_now_local():difference(timestamp) / 1000000

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
