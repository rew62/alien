#!/bin/bash
# Display music infomation using playerctl
# v1.0 2026-05-18 @rew62

PCTL=$(playerctl status 2>/dev/null)
[[ -z "$PCTL" || "$PCTL" == "no players found" ]] && exit 0

case "$1" in
  artist)
    playerctl metadata xesam:artist 2>/dev/null | xargs | cut -b 1-25
    ;;
  title)
    playerctl metadata xesam:title 2>/dev/null | cut -b 1-38
    ;;
  display)
    ARTIST=$(playerctl metadata xesam:artist 2>/dev/null | xargs | cut -b 1-25)
    TITLE=$(playerctl metadata xesam:title 2>/dev/null | cut -b 1-38)
    echo "${ARTIST} - ${TITLE}"
    ;;
  status)
    echo "$PCTL"
    ;;
  time)
    POS=$(playerctl position 2>/dev/null)
    [[ -z "$POS" ]] && exit 0
    pos_sec=$(printf "%.0f" "$POS")
    cur=$(printf "%d:%02d" $((pos_sec / 60)) $((pos_sec % 60)))
    LEN=$(playerctl metadata mpris:length 2>/dev/null)
    if [[ -n "$LEN" && "$LEN" -gt 0 ]] 2>/dev/null; then
      tot_sec=$(( LEN / 1000000 ))
      tot=$(printf "%d:%02d" $((tot_sec / 60)) $((tot_sec % 60)))
      echo "${cur} / ${tot}"
    else
      echo "${cur}"
    fi
    ;;
esac
