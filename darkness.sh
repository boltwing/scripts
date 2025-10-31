#!/bin/bash

current=$(light -G)  # current brightness

if (( $(echo "$current > 0" | bc -l) )); then
    light -S 0
else
    light -S 18
fi

