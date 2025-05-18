return {
	dock = {
		pinned_apps = {
			"thunar",
			"wezterm",
			"zen",
      "komikku",
			"telegram",
			"obs",
			"codium",
			"resources",
		},
	},
	github = {
		username = "linuxmobile",
	},
	monitor = {
		mode = "primary", -- Can be "primary", "all", or "specific"
		specific_monitor = 1,
	},
	profile = {
		picture = os.getenv("HOME") .. "/Downloads/fastfetch/greenish/fastfech.png",
	},
	media = {
		preferred_players = {
			"zen",
			"firefox",
      "spotify",
		},
	},
	display = {
		night_light_temp_initial = 3500,
	},
}
