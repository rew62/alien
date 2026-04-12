#!/bin/bash
# khal-calendar.sh - khal calendar for conky display
# requires khal - sudo apt install khal, then run khal --configure
# Usage: ./khal-calendar.sh <month_offset> <months> or -y for full year
# v1.1 2026-03-17 @rew62
# Examples:
#   ./khal.sh -1 3    # start 1 month ago, show 3 months
#   ./khal.sh 0 6     # start current month, show 6 months
#   ./khal.sh -y      # full year

if ! command -v khal &> /dev/null; then
    echo "Error: khal is not installed."
    echo "run sudo apt install khal,  and then, khal configure"
    exit 1
fi

OFFSET="${1:-0}"
MONTHS="${2:-3}"

if [ "$1" = "-y" ]; then
    START=$(date +01/01/%Y)
    END=$(date +12/1/%Y)
else
    START=$(date -d "$OFFSET months" +%m/1/%Y)
    END=$(date -d "$OFFSET months + $MONTHS months" +%m/1/%Y)
fi

/usr/bin/khal --color calendar "$START" "$END" \
  | sed 's/[\x01-\x1F\x7F]//g' \
  | sed -e 's/\[1mNo events\[0m//g' \
       -e 's/\[1m/${color1}${font2}/g' \
       -e 's/\[0m/${color white}${font1}/g' \
       -e 's/\[7m/${color green}${font2}/g' \
       -e 's/ *$//g'
