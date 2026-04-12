#!/usr/bin/env bash
# rss-next.sh - Advance to next RSS feed in rotation
#
# v1.1 2026-04-09 @rew62

DIR="$(cd "$(dirname "$0")"; pwd)"
FEEDS="$DIR/feeds.conf"
IDX_FILE="/dev/shm/rss/feed_idx"

TOTAL=$(grep -vc '^\s*#\|^\s*$' "$FEEDS")
CURRENT=$(cat "$IDX_FILE" 2>/dev/null || echo 1)
NEXT=$(( (CURRENT % TOTAL) + 1 ))
echo "$NEXT" > "$IDX_FILE"

# signal daemon to refetch immediately
pkill -USR1 -f rss-daemon.sh 2>/dev/null
