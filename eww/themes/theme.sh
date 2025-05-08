#!/bin/bash
#  ████████╗██╗  ██╗███████╗███╗   ███╗███████╗
#  ╚══██╔══╝██║  ██║██╔════╝████╗ ████║██╔════╝
#     ██║   ███████║█████╗  ██╔████╔██║█████╗
#     ██║   ██╔══██║██╔══╝  ██║╚██╔╝██║██╔══╝
#     ██║   ██║  ██║███████╗██║ ╚═╝ ██║███████╗
#     ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚══════╝Hypr

wall_animation=any

# Current Theme
read -r THEME < "$HOME"/.config/hypr/eww/themes/.theme

# Current Bar
read -r BAR < "$HOME"/.config/hypr/eww/themes/.bar

# Load Theme configs
. "$HOME"/.config/hypr/eww/themes/"$THEME"/theme-config.bash

# Define Terminal colors
set_term_config() {
	# Alacritty

	cat >"$HOME"/.config/alacritty/rice-colors.toml <<-EOF
		# Default colors
		[colors.primary]
		background = "${bg}"
		foreground = "${fg}"

		# Cursor colors
		[colors.cursor]
		cursor = "${fg}"
		text = "${bg}"

		# Normal colors
		[colors.normal]
		black = "${black}"
		red = "${red}"
		green = "${green}"
		yellow = "${yellow}"
		blue = "${blue}"
		magenta = "${magenta}"
		cyan = "${cyan}"
		white = "${white}"

		# Bright colors
		[colors.bright]
		black = "${blackb}"
		red = "${redb}"
		green = "${greenb}"
		yellow = "${yellowb}"
		blue = "${blueb}"
		magenta = "${magentab}"
		cyan = "${cyanb}"
		white = "${whiteb}"
	EOF

}

# Set dunst config
set_dunst_config() {
	dunst_config_file="$HOME/.config/hypr/config/dunst/dunstrc"

	sed -i "$dunst_config_file" \
		-e "s/origin = .*/origin = ${dunst_origin}/" \
		-e "s/offset = .*/offset = ${dunst_offset}/" \
		-e "s/transparency = .*/transparency = ${dunst_transparency}/" \
		-e "s/^corner_radius = .*/corner_radius = ${dunst_corner_radius}/" \
		-e "s/frame_width = .*/frame_width = ${dunst_border}/" \
		-e "s/frame_color = .*/frame_color = \"${dunst_frame_color}\"/" \
		-e "s/font = .*/font = ${dunst_font}/" \
		-e "s/foreground='.*'/foreground='${main}'/" \
		-e "s/icon_theme = .*/icon_theme = \"${dunst_icon_theme}, Adwaita\"/"

	sed -i '/urgency_low/Q' "$dunst_config_file"
	cat >>"$dunst_config_file" <<-_EOF_
		[urgency_low]
		timeout = 3
		background = "${bg-alt}"
		foreground = "${green}"

		[urgency_normal]
		timeout = 5
		background = "${bg-alt}"
		foreground = "${fg}"

		[urgency_critical]
		timeout = 0
		background = "${bg-alt}"
		foreground = "${red}"
	_EOF_

	dunstctl reload "$dunst_config_file"
}

# Define eww colors
set_eww_colors() {
	cat >"$HOME"/.config/hypr/eww/colors.scss <<-EOF
		\$bg: ${bg};
		\$bg-alt: ${accent_color};
		\$fg: ${fg};
		\$black: ${blackb};
		\$red: ${red};
		\$green: ${green};
		\$yellow: ${yellow};
		\$blue: ${blue};
		\$magenta: ${magenta};
		\$cyan: ${cyan};
		\$archicon: ${arch_icon};
		\$orange: ${orange};
		\$pink: ${pink};
		\$brown: ${brown};
		\$purple: ${purple};
		\$teal: ${teal};
		\$lime: ${lime};
		\$amber: ${amber};
		\$indigo: ${indigo};
		\$grey: ${grey};
		\$main: ${main};
	EOF
}

# Define dock colors
set_nwg_colors() {
	cat >"$HOME/.config/nwg-dock-hyprland/shared.css" <<-EOF
		@define-color background ${bg};
		@define-color bg-alt ${accent_color};
		@define-color foreground ${fg};
		@define-color main ${main};
		@define-color green ${green};
		@define-color red ${red};
		@define-color blue ${blue};
		@define-color pink ${pink};
		@define-color purple ${purple};
		@define-color yellow ${yellow};
	EOF
}

set_launchers() {
	# Rofi launcher
	cat >"$HOME"/.config/hypr/eww/themes/rofi/shared.rasi <<-EOF
		* {
		    font: "${rofi_font}";
		    background: ${rofi_background};
		    bg-alt: ${rofi_bg_alt};
		    background-alt: ${rofi_background_alt};
		    foreground: ${rofi_fg};
		    selected: ${rofi_selected};
		    active: ${rofi_active};
		    urgent: ${rofi_urgent};
		}
	EOF
}

# Define Geany Theme
set_geany(){
	sed -i "$HOME"/.config/geany/geany.conf \
		-e "s/color_scheme=.*/color_scheme=$geany_theme.conf/g"
}

if pgrep -x "geany" > /dev/null; then
    pkill geany
    geany &
fi

# Apply Colors
set_geany
set_launchers
set_term_config
set_dunst_config
set_nwg_colors

# Load current wallpaper
. "$HOME"/.config/hypr/eww/themes/"$THEME"/walls/.wallpaper


remove_hash() {
    echo "${1//#/}"
}

# Set Wallpaper n hyprland borders colors
if [[ "$THEME" == "Pywal" ]]; then
    wal -i "$wallpaper"
    swww img "$wallpaper" --transition-type "$wall_animation"
    # Change Hyprland Borders color
	FOCUSED=$(remove_hash "$main")
	UNFOCUSED=$(remove_hash "$accent_color")
	sed -i "s/^\$borders_focused = .*/\$borders_focused = $FOCUSED/" ~/.config/hypr/hyprland.conf
	sed -i "s/^\$borders_unfocused = .*/\$borders_unfocused = $UNFOCUSED/" ~/.config/hypr/hyprland.conf
    else
    swww img "$wallpaper" --transition-type "$wall_animation"
    # Change Hyprland Borders color
	FOCUSED=$(< ~/.config/hypr/eww/themes/$THEME/.focused)
	UNFOCUSED=$(< ~/.config/hypr/eww/themes/$THEME/.unfocused)
	sed -i "s/^\$borders_focused = .*/\$borders_focused = $FOCUSED/" ~/.config/hypr/hyprland.conf
	sed -i "s/^\$borders_unfocused = .*/\$borders_unfocused = $UNFOCUSED/" ~/.config/hypr/hyprland.conf
fi

# Apply Gtk Theme
gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
gsettings set org.gnome.desktop.interface icon-theme "$gtk_icons"

# Aplly Btop Theme
sed -i "s/^color_theme = \".*\"/color_theme = \"$btop_theme\"/" "$HOME/.config/btop/btop.conf"


# User Envirotment
FLAGS_DIR="$HOME/.config/hypr/eww/scripts"

# Kill Dock process
kill_process() {
    local process_name="$1"
    local pids
    pids=$(pgrep -f "$process_name")

    if [[ -n "$pids" ]]; then
        echo "Matando procesos de: $process_name"
        echo "$pids" | xargs kill -9
        sleep 0.5
    else
        echo "No se encontraron procesos activos de: $process_name"
    fi
}

# Read flags
read_flag() {
    local flag_file="$FLAGS_DIR/$1"
    if [[ -f "$flag_file" ]]; then
        cat "$flag_file"
    else
        echo ""
    fi
}

# Dock location and autohide
handle_dock() {
    local dock_flag
    dock_flag=$(read_flag ".dock")

    if [[ "$dock_flag" == "on" ]]; then
        kill_process "nwg-dock-hyprland"

        local location autohide extra_args=""
        location=$(read_flag ".docklocation")
        autohide=$(read_flag ".autohide")

        # Add -p (location)
        if [[ -n "$location" ]]; then
            extra_args="$extra_args -p $location"
        fi

        # Add -d if autohide is on
        if [[ "$autohide" == "on" ]]; then
            extra_args="$extra_args -d"
        fi

        # final command
        local dock_cmd="nwg-dock-hyprland -i 32 -w 5 -mb 5 -ml 5 -mr 5 -x -s style.css$extra_args -c 'rofi -show drun -theme $HOME/.config/hypr/eww/themes/rofi/Launcher.rasi'"
        echo "Running: $dock_cmd"
        eval "$dock_cmd &"
    else
        echo "Dock off."
    fi
}

# Run commands funtion
check_flag_and_run() {
    local flag="$1"
    local command="$2"
    local kill_name="$3"

    if [[ -f "$FLAGS_DIR/$flag" ]]; then
        if grep -q "^on$" "$FLAGS_DIR/$flag"; then
            echo "Flag '$flag' on. Running command..."
            if [[ -n "$kill_name" ]]; then
                kill_process "$kill_name"
            fi
            eval "$command &"
        else
            echo "Flag '$flag' off."
        fi
    else
        echo "Flag '$flag' missing."
    fi
}

# Kill and reload eww daemon
killall eww && sleep 0.7 && eww daemon -c ~/.config/hypr/eww/ && eww daemon -c ~/.config/hypr/eww/volume &

# Apply eww colors
set_eww_colors

# Open users configs (bar, dock etc etc)
check_flag_and_run ".panel" "xfce4-panel"
handle_dock
check_flag_and_run ".desktopclock" "eww open desktopclock -c '$HOME/.config/hypr/eww'"
check_flag_and_run ".desktopinfo" "eww open desktopinfo -c '$HOME/.config/hypr/eww'"
check_flag_and_run ".bar" "eww open $BAR -c '$HOME/.config/hypr/eww'"

