#!/bin/bash

direc="$HOME/captured/screen/"
mkdir -p direc

file="$direc/$(date +'%y-%-m-%-d_%H:%M_%S').png"

case "$1" in
  full)
    import -window root "$file"
    ;;
  window)
    import -frame "$file"
    ;;
  select|area)
    import "$file"
    ;;
  *)
    echo "Usage: $0 {full|window|select}"
    exit 1
    ;;
esac

notify-send "Screenshot saved" "$file"
echo "Saved: $file"

