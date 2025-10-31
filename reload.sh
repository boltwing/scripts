#!/bin/bash

# kill waybar
pkill waybar

# reload waybar
nohup waybar >/dev/null 2>&1 &
disown

hyprctl reload

if command -v notify-send >/dev/null; then
    notify-send "RELOADED!"
fi

