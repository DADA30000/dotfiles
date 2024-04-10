#!/bin/bash
WALLPAPER_PATH="$(pwd)/wallpaper.png"

echo "Setting wallpaper..."
swww img $WALLPAPER_PATH --transition-type random --transition-fps 60
