#!/usr/bin/env bash
# rss-click.sh - Handle click events on RSS conky widget
#
# v1.1 2026-04-09 @rew62

DIR="$(cd "$(dirname "$0")"; pwd)"
MAP="/dev/shm/rss/rss.map"

# get mouse position relative to screen
eval $(xdotool getmouselocation --shell)
MOUSE_X=$X
MOUSE_Y=$Y

# get Conky window position dynamically
eval $(xdotool search --name "rss" getwindowgeometry --shell 2>/dev/null | head -5)
CONKY_LEFT=${X:-0}
#CONKY_TOP=${Y:-100}
CONKY_TOP=$(( ${Y:-100} + 16 ))
LINE_HEIGHT=16

# calculate which line was clicked
INDEX=$(( (MOUSE_Y - CONKY_TOP) / LINE_HEIGHT + 1 ))

# get action from map
ACTION=$(awk -F'|' -v i=$INDEX '$1==i {print $2}' "$MAP")

echo "$(date '+%T') X=$MOUSE_X Y=$MOUSE_Y CONKY_LEFT=$CONKY_LEFT CONKY_TOP=$CONKY_TOP INDEX=$INDEX ACTION='$ACTION'" >> /tmp/rss-click.log

if [ "$ACTION" = "next" ]; then
    "$DIR/rss-next.sh"
elif [ -n "$ACTION" ]; then
    xdg-open "$ACTION" 2>/dev/null
fi
