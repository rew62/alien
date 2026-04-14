#!/usr/bin/env bash
# save-pos.sh — Read current xdotool position of conky windows and write
#               back the computed gap_x / gap_y into their .rc files.
#
# Usage:
#   ./save-pos.sh              # update all known windows
#   ./save-pos.sh rss          # update one window by title keyword
#   ./save-pos.sh rss sys-small current
#
#   NOTE: THIS IS EXPERIMENTAL.
#   Use Alt+Mouse to drag conky windows to desired location
#   Script will comment out Alignment var in config and use absolute coordinates based on screen size.
#   Conky the redraws at the next interval, however some intervals are long since they do not change as often.
#   To redraw longer conkys with long intervals you will need to stop/restart the conky.rc file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Window-title → rc-file mapping
#   KEY  = string passed to "xdotool search --name <KEY>"  (first match used)
#   VALUE = path to the .rc file
# ---------------------------------------------------------------------------
declare -A RC_FILE
RC_FILE["rss"]="$SCRIPT_DIR/rss/rss.rc"
RC_FILE["sys-small"]="$SCRIPT_DIR/calendar/sys-small.rc"
RC_FILE["current"]="$SCRIPT_DIR/weather/current.rc"
RC_FILE["forecast"]="$SCRIPT_DIR/weather/forecast.rc"
RC_FILE["full"]="$SCRIPT_DIR/weather/full.rc"
RC_FILE["song-info"]="$SCRIPT_DIR/clock/song-info.rc"
RC_FILE["clock"]="$SCRIPT_DIR/clock/clock.rc"
RC_FILE["vnstat"]="$SCRIPT_DIR/vnstat/vnstat.rc"
RC_FILE["hcal2"]="$SCRIPT_DIR/calendar/hcal2.rc"
RC_FILE["hcal"]="$SCRIPT_DIR/calendar/hcal.rc"
RC_FILE["arc"]="$SCRIPT_DIR/arc/arc.rc"
RC_FILE["sp-cal"]="$SCRIPT_DIR/calendar/sidepanel-calendar.rc"
RC_FILE["khal-cal"]="$SCRIPT_DIR/calendar/kcalendar.rc"
RC_FILE["ac-cal"]="$SCRIPT_DIR/calendar/lcalendar.rc"
RC_FILE["earth"]="$SCRIPT_DIR/earth/earth.rc"
RC_FILE["gcal"]="$SCRIPT_DIR/gcal/gcal.rc"
RC_FILE["stocks"]="$SCRIPT_DIR/stocks/ticker.rc"

# Full window titles (used for xdotool --name exact search when needed).
# If the key already uniquely matches, this is not needed — but listed for clarity.
declare -A WIN_TITLE
WIN_TITLE["rss"]="rss"
WIN_TITLE["sys-small"]="sys-small"
WIN_TITLE["current"]="w-current"
WIN_TITLE["forecast"]="w-forecast"
WIN_TITLE["full"]="w-full"
WIN_TITLE["song-info"]="song-info"
WIN_TITLE["clock"]="conky_clock"
WIN_TITLE["vnstat"]="vnstat"
WIN_TITLE["hcal2"]="hcal2"
WIN_TITLE["hcal"]="hcal"
WIN_TITLE["arc"]="conky-arc"
WIN_TITLE["sp-cal"]="sp-cal"
WIN_TITLE["khal-cal"]="khal-cal"
WIN_TITLE["ac-cal"]="ac-cal"
WIN_TITLE["earth"]="earth"
WIN_TITLE["gcal"]="gcal"

# ---------------------------------------------------------------------------
# Helper: integer division (bash only does integers anyway)
# ---------------------------------------------------------------------------
idiv() { echo $(( $1 / $2 )); }

# ---------------------------------------------------------------------------
# Get primary screen dimensions via xrandr, then workarea via _NET_WORKAREA
# Conky positions windows relative to the workarea (excludes panels/docks).
# Sets: SCREEN_W SCREEN_H  WA_X WA_Y WA_W WA_H
# ---------------------------------------------------------------------------
get_screen_size() {
    local info
    info=$(xrandr | awk '/ connected .*primary/{print; exit}
                         / connected /{line=$0} END{if(!found)print line}')
    SCREEN_W=$(echo "$info" | grep -oP '\d+x\d+' | head -1 | cut -dx -f1)
    SCREEN_H=$(echo "$info" | grep -oP '\d+x\d+' | head -1 | cut -dx -f2)
    if [[ -z "$SCREEN_W" || -z "$SCREEN_H" ]]; then
        echo "ERROR: could not determine screen size from xrandr" >&2
        exit 1
    fi

    # Read workarea (x, y, w, h) from the window manager — first desktop entry
    local wa
    wa=$(xprop -root _NET_WORKAREA 2>/dev/null | grep -oP '\d+' | head -4)
    WA_X=$(echo "$wa" | sed -n '1p')
    WA_Y=$(echo "$wa" | sed -n '2p')
    WA_W=$(echo "$wa" | sed -n '3p')
    WA_H=$(echo "$wa" | sed -n '4p')
    # Fall back to full screen if workarea unavailable
    if [[ -z "$WA_X" || -z "$WA_Y" || -z "$WA_W" || -z "$WA_H" ]]; then
        WA_X=0; WA_Y=0; WA_W=$SCREEN_W; WA_H=$SCREEN_H
    fi
}

# ---------------------------------------------------------------------------
# Get window geometry via xdotool
# Returns global WIN_X WIN_Y WIN_W WIN_H
# ---------------------------------------------------------------------------
get_window_geometry() {
    local title_key="$1"
    local title="${WIN_TITLE[$title_key]}"

    # xdotool search returns one ID per line; take the first
    local wid
    wid=$(xdotool search --name "$title" 2>/dev/null | head -1)
    if [[ -z "$wid" ]]; then
        return 1
    fi

    local geom
    geom=$(xdotool getwindowgeometry "$wid" 2>/dev/null)

    # Position: "  Position: 2665,575 (screen: 0)"
    WIN_X=$(echo "$geom" | grep -oP 'Position:\s*\K\d+(?=,)')
    WIN_Y=$(echo "$geom" | grep -oP 'Position:\s*\d+,\K\d+')
    # Geometry: "  Geometry: 430x173"
    WIN_W=$(echo "$geom" | grep -oP 'Geometry:\s*\K\d+(?=x)')
    WIN_H=$(echo "$geom" | grep -oP 'Geometry:\s*\d+x\K\d+')

    if [[ -z "$WIN_X" || -z "$WIN_Y" || -z "$WIN_W" || -z "$WIN_H" ]]; then
        echo "  SKIP: could not parse geometry for '$title'" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Read the current alignment from an .rc file
# ---------------------------------------------------------------------------
get_alignment() {
    local rc="$1"
    grep -oP "alignment\s*=\s*['\"]?\K[a-z_]+" "$rc" 2>/dev/null | head -1 || true
}

# ---------------------------------------------------------------------------
# Compute gap_x / gap_y from absolute position + alignment + screen size
#
# Conky places windows using raw screen coordinates (origin 0,0), not
# workarea-relative. The formulas below are the inverse of conky's placement:
#   left:   win_x = gap_x              → gap_x = win_x
#   right:  win_x = sw - ww - gap_x   → gap_x = sw - ww - win_x
#   middle: win_x = sw/2 - ww/2 + gap_x → gap_x = win_x - sw/2 + ww/2
#   top:    win_y = gap_y              → gap_y = win_y
#   bottom: win_y = sh - wh - gap_y   → gap_y = sh - wh - win_y
#   middle: win_y = sh/2 - wh/2 + gap_y → gap_y = win_y - sh/2 + wh/2
# ---------------------------------------------------------------------------
compute_gaps() {
    local align="$1"
    local px=$2 py=$3 ww=$4 wh=$5
    local sw=$SCREEN_W sh=$SCREEN_H

    local vpart hpart
    vpart="${align%%_*}"   # top / bottom / middle / none
    hpart="${align##*_}"   # left / right / middle / none (same as vpart when align='none')

    # When alignment is a bare word like 'none' or 'middle', treat as middle/middle
    if [[ "$vpart" == "$hpart" ]]; then
        vpart="middle"; hpart="middle"
    fi

    case "$hpart" in
        left)   GAP_X=$px ;;
        right)  GAP_X=$(( sw - ww - px )) ;;
        middle) GAP_X=$(( px - sw/2 + ww/2 )) ;;
        *)      GAP_X=$px ;;
    esac

    case "$vpart" in
        top)    GAP_Y=$py ;;
        bottom) GAP_Y=$(( sh - wh - py )) ;;
        middle) GAP_Y=$(( py - sh/2 + wh/2 )) ;;
        *)      GAP_Y=$py ;;
    esac
}

# ---------------------------------------------------------------------------
# Patch gap_x and gap_y in the .rc file using sed
# Handles arbitrary whitespace and optional quotes around values
# ---------------------------------------------------------------------------
patch_rc() {
    local rc="$1" gx=$2 gy=$3 comment_align="${4:-no}" old_gx="${5:-}" old_gy="${6:-}"

    # Single write so conky only sees one modification and reloads once
    if [[ "$comment_align" == "yes" ]]; then
        local note="-- Alignment commented out by save-pos.sh and gaps updated - previous gaps were gap_x=${old_gx}, gap_y=${old_gy}"
        sed -i -E \
            -e "s/^(\s*gap_x\s*=\s*)[^,]*(,)/\1${gx}\2/" \
            -e "s/^(\s*gap_y\s*=\s*)[^,]*(,)/\1${gy}\2/" \
            -e "s/^(\s*)(alignment\s*=)/\1${note}\n\1-- \2/" \
            "$rc"
    else
        sed -i -E \
            -e "s/^(\s*gap_x\s*=\s*)[^,]*(,)/\1${gx}\2/" \
            -e "s/^(\s*gap_y\s*=\s*)[^,]*(,)/\1${gy}\2/" \
            "$rc"
    fi
}

# ---------------------------------------------------------------------------
# Process one window
# ---------------------------------------------------------------------------
process() {
    local key="$1"
    local rc="${RC_FILE[$key]}"

    if [[ ! -f "$rc" ]]; then
        return
    fi

    get_window_geometry "$key" || return

    echo "--- $key ---"

    # Track whether alignment was actually in the file (vs defaulted)
    local orig_align
    orig_align=$(get_alignment "$rc")
    local align="${orig_align:-bottom_left}"

    compute_gaps "$align" "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H"

    # Read what's currently stored
    local old_gx old_gy
    old_gx=$(grep -oP '^\s*gap_x\s*=\s*\K[^,]+' "$rc" | tr -d ' \n' || true)
    old_gy=$(grep -oP '^\s*gap_y\s*=\s*\K[^,]+' "$rc" | tr -d ' \n' || true)

    # Detect movement and decide whether to override alignment
    local comment_align="no"
    if [[ "$GAP_X" != "$old_gx" || "$GAP_Y" != "$old_gy" ]]; then
        if [[ -n "$orig_align" ]]; then
            # Window moved and has alignment — switch to absolute bottom_left positioning
            compute_gaps "bottom_left" "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H"
            comment_align="yes"
        fi
    fi

    echo "  window  : pos=($WIN_X,$WIN_Y) size=${WIN_W}x${WIN_H}"
    echo "  screen  : ${SCREEN_W}x${SCREEN_H}  workarea: ${WA_W}x${WA_H} at (${WA_X},${WA_Y})"
    echo "  align   : ${orig_align:-(none, using bottom_left)}"
    echo "  new gaps: gap_x=$GAP_X  gap_y=$GAP_Y"
    echo "  old gaps: gap_x=$old_gx  gap_y=$old_gy"
    [[ "$comment_align" == "yes" ]] && echo "  note    : alignment overridden (window moved)"

    patch_rc "$rc" "$GAP_X" "$GAP_Y" "$comment_align" "$old_gx" "$old_gy"
    echo "  updated : $rc"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
get_screen_size

if [[ $# -eq 0 ]]; then
    for key in "${!RC_FILE[@]}"; do
        process "$key" || true
    done
else
    for key in "$@"; do
        if [[ -z "${RC_FILE[$key]+_}" ]]; then
            echo "Unknown window key '$key'. Known keys: ${!RC_FILE[*]}" >&2
            exit 1
        fi
        process "$key" || true
    done
fi
