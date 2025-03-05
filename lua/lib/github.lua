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

local last_rate_check = 0
local last_rate_status = true
local last_rate_remaining = 60

local Github = {
	get_events = nil,
	format_time = nil,
	POLL_INTERVAL = POLL_INTERVAL,
}

local config_path = debug.getinfo(1).source:match("@?(.*/)") .. "../../user-variables.lua"
local user_vars = loadfile(config_path)()

local function exponential_backoff(attempt)
	return RETRY_DELAY * (2 ^ (attempt - 1))
end

local function ensure_cache_dir()
	if not GLib.file_test(CACHE_DIR, "EXISTS") then
		GLib.mkdir_with_parents(CACHE_DIR, 0755)
	end
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

	local parse_success, cache = pcall(cjson.decode, content)
	if not parse_success or type(cache) ~= "table" then
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
	local cache = {
		timestamp = os.time(),
		events = events,
	}

	local success, encoded = pcall(cjson.encode, cache)
	if not success then
		return false
	end

	local temp_file = CACHE_FILE .. ".tmp"
	local write_success = pcall(function()
		astal.write_file(temp_file, encoded)
	end)

	if not write_success then
		pcall(os.remove, temp_file)
		return false
	end

	local rename_success = pcall(function()
		os.rename(temp_file, CACHE_FILE)
	end)

	if not rename_success then
		pcall(os.remove, temp_file)
		return false
	end

	return true
end

local function check_rate_limit()
	local current_time = os.time()
	if current_time - last_rate_check < RATE_CHECK_INTERVAL then
		Debug.debug("GitHub", "Using cached rate limit status (remaining: %d)", last_rate_remaining)
		return last_rate_status
	end

	Debug.debug("GitHub", "Performing fresh rate limit check")
	local rate_limit_check = astal.exec({
		"curl",
		"-sI",
		"https://api.github.com/rate_limit",
		"-H",
		"Accept: application/vnd.github+json",
	})

	if rate_limit_check then
		local remaining = tonumber(rate_limit_check:match("x%-ratelimit%-remaining: (%d+)"))
		if remaining then
			last_rate_remaining = remaining
			Debug.debug("GitHub", "Rate limit remaining: %d", remaining)
			if remaining < 10 then
				last_rate_status = false
				last_rate_check = current_time
				return false
			end
		end
	end

	last_rate_status = true
	last_rate_check = current_time
	return true
end

local function fetch_github_events(username, attempt)
	attempt = attempt or 1
	Debug.debug("GitHub", "Starting fetch attempt %d for user %s", attempt, username)

	if attempt > MAX_RETRIES then
		Debug.warn("GitHub", "Max retries reached, aborting fetch")
		return nil, "max_retries"
	end

	if not check_rate_limit() then
		Debug.warn("GitHub", "Rate limit nearly exceeded, backing off")
		return nil, "rate_limit"
	end

	local url = string.format("https://api.github.com/users/%s/received_events", username)
	Debug.debug("GitHub", "Fetching from URL: %s", url)

	local curl_cmd = {
		"curl",
		"-s",
		"-S",
		"--compressed",
		"--max-time",
		"5",
		"-H",
		"Accept: application/json",
		"-H",
		"Accept-Encoding: gzip, deflate, br",
		"-H",
		"User-Agent: astal-bar",
		"-H",
		"Connection: keep-alive",
		url,
	}

	Debug.debug("GitHub", "Executing curl request")
	local output = astal.exec(curl_cmd)
	if not output then
		Debug.warn("GitHub", "Request failed")
		if attempt < MAX_RETRIES then
			local delay = exponential_backoff(attempt)
			Debug.debug("GitHub", "Retrying in %d seconds", delay)
			astal.sleep(exponential_backoff(attempt))
			return fetch_github_events(username, attempt + 1)
		end
		return nil, "network_error"
	end

	Debug.debug("GitHub", "Parsing response")
	local success, events = pcall(cjson.decode, output)
	if not success or type(events) ~= "table" then
		Debug.error("GitHub", "Failed to parse response: %s", success and "invalid format" or events)
		return nil, "parse_error"
	end

	Debug.info("GitHub", "Successfully fetched %d events", #events)
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
	Debug.debug("GitHub", "Starting events fetch process")
	ensure_cache_dir()

	local cached_events, is_expired = load_cache()
	if cached_events and not is_expired then
		Debug.info("GitHub", "Using valid cache with %d events", #cached_events)
		return filter_events(cached_events)
	end

	local username = user_vars.github and user_vars.github.username or "linuxmobile"
	Debug.debug("GitHub", "Fetching fresh events for user: %s", username)

	local events, error_type = fetch_github_events(username)

	if events and #events > 0 then
		Debug.debug("GitHub", "Saving %d events to cache", #events)
		save_cache(events)
		local filtered = filter_events(events)
		Debug.info("GitHub", "Returning %d filtered events", #filtered)
		return filtered
	end

	if error_type == "rate_limit" and cached_events then
		Debug.warn("GitHub", "Rate limited, falling back to cache")
		return filter_events(cached_events)
	end

	Debug.warn("GitHub", "No events available, returning empty or cached list")
	return cached_events and filter_events(cached_events) or {}
end

function Github.format_time(iso_time)
	if not iso_time then
		return "unknown time"
	end

	local timestamp = GLib.DateTime.new_from_iso8601(iso_time, nil)
	if not timestamp then
		return "invalid time"
	end

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
