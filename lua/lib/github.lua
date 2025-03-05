local astal = require("astal")
local cjson = require("cjson")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")

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

local function fetch_with_wget(url)
	Debug.debug("GitHub", "Starting wget fetch")
	local temp_file = os.tmpname()
	Debug.debug("GitHub", "Using temporary file: %s", temp_file)

	local wget_cmd = {
		"wget",
		"--quiet",
		"--timeout=5",
		"--header=Accept: application/vnd.github+json",
		"--header=User-Agent: astal-bar",
		"-O",
		temp_file,
		url,
	}

	local _, err = astal.exec(wget_cmd)
	if err then
		Debug.error("GitHub", "Wget error: %s", err)
		os.remove(temp_file)
		return nil
	end

	local file = io.open(temp_file, "r")
	if not file then
		Debug.error("GitHub", "Failed to read wget output file")
		os.remove(temp_file)
		return nil
	end

	Debug.debug("GitHub", "Reading wget response")
	local content = file:read("*all")
	file:close()
	os.remove(temp_file)

	if not content or content == "" then
		Debug.error("GitHub", "Empty response from wget")
		return nil
	end

	Debug.debug("GitHub", "Wget fetch completed successfully")
	return content
end

local function fetch_github_events(username)
	Debug.info("GitHub", "Fetching GitHub events for user: %s", username)
	local url = string.format("https://api.github.com/users/%s/received_events", username)
	Debug.debug("GitHub", "Request URL: %s", url)

	local curl_cmd = {
		"curl",
		"-s", -- silent
		"-S", -- show errors
		"--compressed", -- handle compression
		"--max-time",
		"5", -- timeout
		"-H",
		"Accept: application/json",
		"-H",
		"Accept-Encoding: gzip, deflate, br",
		"-H",
		"User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
		"-H",
		"Connection: keep-alive",
		url,
	}

	Debug.debug("GitHub", "Executing curl request")
	local output = astal.exec(curl_cmd)

	if not output then
		Debug.warn("GitHub", "Curl failed, attempting wget")
		Debug.debug("GitHub", "Starting wget fallback")
		output = fetch_with_wget(url)
		Debug.debug("GitHub", "Wget attempt completed")
	end

	if not output then
		Debug.error("GitHub", "Both curl and wget failed")
		return nil
	end

	Debug.debug("GitHub", "Parsing JSON response")
	local success, events = pcall(cjson.decode, output)
	if not success then
		Debug.error("GitHub", "Failed to parse JSON response: %s", events)
		Debug.debug("GitHub", "Raw response: %s", output:sub(1, 100))
		return nil
	end

	if type(events) ~= "table" then
		Debug.error("GitHub", "Unexpected response type: %s", type(events))
		return nil
	end

	Debug.info("GitHub", "Successfully fetched %d events", #events)
	return events
end

local function check_network()
	Debug.debug("GitHub", "Checking network connectivity")
	local curl_cmd = {
		"curl",
		"-s",
		"--compressed",
		"-m",
		"2",
		"-H",
		"Accept: application/json",
		"-H",
		"Accept-Encoding: gzip, deflate, br",
		"-H",
		"User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
		"-H",
		"Connection: keep-alive",
		"--head",
		"https://api.github.com",
	}

	local output = astal.exec(curl_cmd)
	if not output then
		Debug.error("GitHub", "Network check failed - no response")
		return false
	end

	if not output:match("^HTTP/[%d%.]+ 200") then
		Debug.error("GitHub", "Network check failed - bad response")
		return false
	end

	Debug.debug("GitHub", "Network check successful")
	return true
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

	Debug.debug("GitHub", "Starting events fetch process")

	local cached_events = load_cache()
	if cached_events then
		Debug.info("GitHub", "Using cached events")
		return filter_events(cached_events)
	end

	if not check_network() then
		Debug.warn("GitHub", "Network appears to be down")
		return {}
	end

	local username = user_vars.github and user_vars.github.username or "linuxmobile"
	Debug.debug("GitHub", "Attempting to fetch events for: %s", username)

	local events = fetch_github_events(username)

	if events and #events > 0 then
		Debug.debug("GitHub", "Saving events to cache")
		save_cache(events)
		local filtered = filter_events(events)
		Debug.info("GitHub", "Returning %d filtered events", #filtered)
		return filtered
	end

	Debug.warn("GitHub", "No events found, returning empty list")
	return {}
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
