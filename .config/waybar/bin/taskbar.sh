#!/bin/bash
read title
hyprctl dispatch movetoworkspace 10,title:^($title)$
