#!/bin/bash

SYMBOLS_FILE="$HOME/.config/hypr/eww/themes/rofi/nerdfont-icons.txt"

SELECTED=$(cat "$SYMBOLS_FILE" | rofi -dmenu -i -theme $HOME/.config/hypr/eww/themes/rofi/icons.rasi)

CHAR=$(echo "$SELECTED" | awk '{print $1}')

if [ -n "$CHAR" ]; then
  echo -n "$CHAR" | wl-copy
fi
