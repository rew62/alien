#!/usr/bin/env bash
# rss-daemon.sh - Background daemon to auto-refresh RSS feeds
#
# v1.1 2026-04-09 @rew62

DIR="$(cd "$(dirname "$0")"; pwd)"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

# --- bind clicks (retry if window changes) ---
(
    LAST_WIN=""

    while true; do
        WIN=$(xdotool search --name "^rss$" 2>/dev/null | tail -n 1)

        if [ -n "$WIN" ] && [ "$WIN" != "$LAST_WIN" ]; then
            echo "[rss] binding to $WIN"
            LAST_WIN="$WIN"

            # kill any previous behave attached to old window
            pkill -f "xdotool behave.*rss-click.sh" 2>/dev/null

            xdotool behave "$WIN" mouse-click exec "$DIR/rss-click.sh" &
        fi

        sleep 1
    done
) &

# --- self-terminate when window disappears ---
(
    sleep 30
    while xdotool search --name "^rss$" >/dev/null 2>&1; do
        sleep 60
    done
    kill $$
) &

# --- fetch loop ---
SLEEP_PID=
trap 'kill $SLEEP_PID 2>/dev/null' USR1

while true; do
    "$DIR/rss-fetch.sh"
    sleep 600 &
    SLEEP_PID=$!
    wait $SLEEP_PID 2>/dev/null
done
