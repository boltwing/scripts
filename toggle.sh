#!/bin/bash

target="$1"

if [ -z "$target" ]; then
    exit 1
fi

if pgrep -x "$target" > /dev/null; then
    pkill -x "$target"
else
    "$target" &
fi

