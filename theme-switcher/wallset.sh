#!/bin/bash

# Directory containing wallpapers
WALL_DIR="$HOME/Pictures/background"

# Current directory (to cd back to)
CWD="$(pwd)"

cd "$WALL_DIR" || exit

# Handle spaces in filenames
IFS=$'\n'

# Grab the user-selected wallpaper
SELECTED_WALL=$(for a in *.jpg *.png; do echo -en "$a\Bicon\xlf$a\n"; done | rofi -dmenu -p "")

# If not empty, pass to walset-backend
if [ -n "$SELECTED_WALL" ]; then
  walset-backend "$SELECTED_WALL"
fi

# Go back to where you came from
cd "$CWD" || exit
