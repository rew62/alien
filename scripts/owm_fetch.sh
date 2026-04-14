#!/usr/bin/env bash
# owm_fetch.sh - Unified OWM fetch for arc, weather-current, and calendar conkys
# Non-blocking background fetch; all callers share one cache (file-age gate)
# v1.1 2026-04-09 @rew62
#
# Gate:        file age of owm_current.json vs CACHE_TTL (system clock, not a timer)
# Background:  network fetch is non-blocking; all callers share one cache.
# Icon:        ICON_SOURCE=cdn    → OWM CDN-fetched PNGs cached in /dev/shm/conky/icons/ (default)
#              ICON_SOURCE=local  → local Meteo PNGs from $ALIEN_DIR/icons/ (if dir exists, else falls back to CDN)
#
# Config sources (sourced in order; later values win):
#   ~/.conky/alien/.env          – OWM_API_KEY / LAT / LON / UNITS 
#
# Cache: /dev/shm/conky/
#   owm_current.json    – raw OWM API response
#   owm_parsed.txt      – flat key=value (for owm_get() / owm-current.sh)
#   icons/current.png   – selected weather icon
#   icons/<code>.png    – OWM CDN icon cache
#   owm_fetch.log       – error log
#
# Usage:
#   ${execi 120 ~/.conky/alien/owm_fetch.sh}   ← from any conky config
#   os.execute("~/.conky/alien/owm_fetch.sh &") ← from Lua

set -uo pipefail

ALIEN_DIR="${ALIEN_DIR:-$HOME/.conky/alien}"
CACHE_DIR="${CONKY_CACHE_DIR:-/dev/shm/conky}"
ICON_DIR="$CACHE_DIR/icons"
CACHE_JSON="$CACHE_DIR/owm_current.json"
CACHE_PARSED="$CACHE_DIR/owm_parsed.txt"
TMP_JSON="$CACHE_DIR/.owm_current.tmp"
LOG_FILE="$CACHE_DIR/owm_fetch.log"
LOCK_DIR="$CACHE_DIR/.owm_fetching"   # atomic lock: mkdir succeeds only once

mkdir -p "$CACHE_DIR" "$ICON_DIR"

# ── Credentials and settings ──────────────────────────────────────────────────
[[ -f "$ALIEN_DIR/.env"         ]] && source "$ALIEN_DIR/.env"

# Normalise: prefer uppercase names, fall back to .env lowercase names
OWM_API_KEY="${OWM_API_KEY:-${owm_api_key:-}}"
LAT="${LAT:-${lat:-}}"
LON="${LON:-${lon:-}}"
UNITS="${UNITS:-${units:-imperial}}"
LANG="${LANG:-en}"
CACHE_TTL="${CACHE_TTL:-300}"           # seconds between network fetches
ICON_SOURCE="${ICON_SOURCE:-cdn}"      # "cdn" (OWM CDN, default) or "local" (Meteo PNGs in $ALIEN_DIR/icons/)

if [[ -z "$OWM_API_KEY" || -z "$LAT" || -z "$LON" ]]; then
    echo "$(date -Is) ERROR: OWM_API_KEY / LAT / LON not set" >> "$LOG_FILE"
    exit 1
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

is_cache_fresh() {
    [[ -f "$CACHE_JSON" ]] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$CACHE_JSON" 2>/dev/null || echo 0) ))
    [[ $age -lt $CACHE_TTL ]]
}

wind_cardinal() {
    # Round(deg / 22.5) → 16-point compass index
    local deg=$1
    local dirs=(N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW)
    local idx=$(( (deg * 10 + 112) / 225 % 16 ))
    echo "${dirs[$idx]}"
}

fmt_12h() {
    # Unix timestamp → "9:45a" / "12:00p"
    date -d "@$1" "+%-I:%M%p" 2>/dev/null | tr 'A-Z' 'a-z' | sed 's/am$/a/;s/pm$/p/'
}

title_case() {
    awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}' <<< "$1"
}

metno_name() {
    case "$1" in
      01d) echo clearsky_day       ;; 01n) echo clearsky_night    ;;
      02d) echo fair_day           ;; 02n) echo fair_night         ;;
      03d) echo partlycloudy_day   ;; 03n) echo partlycloudy_night ;;
      04d|04n) echo cloudy         ;;
      09d|09n) echo lightrain      ;;
      10d|10n) echo rain           ;;
      11d|11n) echo rainandthunder ;;
      13d|13n) echo snow           ;;
      50d|50n) echo fog            ;;
      *)       echo partlycloudy_day ;;
    esac
}

uni_icon() {
    case "${1:0:2}" in
      01) echo "☀"  ;; 02) echo "🌤"  ;; 03) echo "⛅"  ;;
      04) echo "☁"  ;; 09) echo "🌧"  ;; 10) echo "🌦"  ;;
      11) echo "⛈"  ;; 13) echo "❄"  ;; 50) echo "🌫"  ;;
      *)  echo "?"  ;;
    esac
}

# ── Icon selection (synchronous, fast, no network) ────────────────────────────
# Runs on every call so the icon stays current near dawn/dusk even without a fetch.

select_icon() {
    [[ -f "$CACHE_JSON" ]] || return 0

    local code
    code=$(jq -r '.weather[0].icon // "01d"' "$CACHE_JSON" 2>/dev/null) || code="01d"

    # Cloud-cover override: during daylight with no precip, map to cloud-band icons
    local now sr ss clouds rain1 snow1
    now=$(date +%s)
    sr=$(jq -r    '.sys.sunrise // 0'    "$CACHE_JSON" 2>/dev/null || echo 0)
    ss=$(jq -r    '.sys.sunset  // 0'    "$CACHE_JSON" 2>/dev/null || echo 0)
    clouds=$(jq -r '.clouds.all  // ""'  "$CACHE_JSON" 2>/dev/null || echo "")
    rain1=$(jq -r  '.rain["1h"] // 0'   "$CACHE_JSON" 2>/dev/null || echo 0)
    snow1=$(jq -r  '.snow["1h"] // 0'   "$CACHE_JSON" 2>/dev/null || echo 0)

    if [[ -n "$clouds" && "$rain1" == "0" && "$snow1" == "0" \
          && "$now" -ge "$sr" && "$now" -le "$ss" ]]; then
        local c=${clouds%.*}
        if   (( c <= 15 )); then code="01d"
        elif (( c <= 40 )); then code="02d"
        elif (( c <= 70 )); then code="03d"
        else                     code="04d"
        fi
    fi

    local src outpng="$ICON_DIR/current.png"

    local LOCAL_ICON_DIR="$ALIEN_DIR/icons"
    if [[ "$ICON_SOURCE" == "local" && -d "$LOCAL_ICON_DIR" ]]; then
        # Use local Meteo icons from repo icons/ dir; fall back to CDN cache if file missing
        src="$LOCAL_ICON_DIR/${code}.png"
        [[ -f "$src" ]] || src="$LOCAL_ICON_DIR/$(echo "$code" | sed 's/n$/d/').png"
        [[ -f "$src" ]] || src="$ICON_DIR/${code}.png"
    else
        # Use OWM CDN-fetched icon (default)
        src="$ICON_DIR/${code}.png"
        [[ -f "$src" ]] || src="$ICON_DIR/$(echo "$code" | sed 's/n$/d/').png"
    fi
    [[ -f "$src" ]] && { cp -f "$src" "${outpng}.tmp" && mv -f "${outpng}.tmp" "$outpng"; } || true
}

# ── Parse JSON → owm_parsed.txt + wind arrow SVG ─────────────────────────────

parse_and_write() {
    [[ -f "$CACHE_JSON" ]] || return 1

    local temp feels_like temp_max temp_min humidity pressure_hpa pressure_inhg
    local wind_speed wind_deg icon_code sunrise sunset loc desc

    temp=$(jq         'if .main.temp      then (.main.temp      + 0.5)|floor else 0 end' "$CACHE_JSON")
    feels_like=$(jq   'if .main.feels_like then (.main.feels_like + 0.5)|floor else 0 end' "$CACHE_JSON")
    temp_max=$(jq     'if .main.temp_max  then (.main.temp_max  + 0.5)|floor else 0 end' "$CACHE_JSON")
    temp_min=$(jq     'if .main.temp_min  then (.main.temp_min  + 0.5)|floor else 0 end' "$CACHE_JSON")
    humidity=$(jq     '.main.humidity  // 0'           "$CACHE_JSON")
    pressure_hpa=$(jq '.main.pressure  // 0'           "$CACHE_JSON")
    pressure_inhg=$(awk "BEGIN { printf \"%.2f\", $pressure_hpa * 0.02953 }")
    wind_speed=$(jq   'if .wind.speed then (.wind.speed + 0.5)|floor else 0 end' "$CACHE_JSON")
    wind_deg=$(jq     '.wind.deg  // 0'                "$CACHE_JSON")
    icon_code=$(jq -r '.weather[0].icon // "01d"'      "$CACHE_JSON")
    sunrise=$(jq -r   '.sys.sunrise // 0'              "$CACHE_JSON")
    sunset=$(jq -r    '.sys.sunset  // 0'              "$CACHE_JSON")
    loc=$(jq -r       '.name // "Unknown"'             "$CACHE_JSON")
    desc=$(title_case "$(jq -r '.weather[0].description // ""' "$CACHE_JSON")")

    local wind_card icon_metno icon_uni temp_unit wind_unit
    wind_card=$(wind_cardinal "$wind_deg")
    icon_metno=$(metno_name "$icon_code")
    icon_uni=$(uni_icon "$icon_code")
    [[ "$UNITS" == "metric" ]] && temp_unit="°C" wind_unit="kph" \
                                || { temp_unit="°F"; wind_unit="mph"; }

    local sr_fmt ss_fmt now_fmt ts
    sr_fmt=$(fmt_12h "$sunrise")
    ss_fmt=$(fmt_12h "$sunset")
    now_fmt=$(date "+%-I:%M %p")
    ts=$(date +%s)

    # Wind arrow SVG + PNG
    local svg_path="/dev/shm/owm_wind.svg"
    local png_path="/dev/shm/owm_wind.png"
    local arrow_deg=$(( (wind_deg + 180) % 360 ))
    local thick
    thick=$(awk "BEGIN { t=1+$wind_speed/3.0; if(t>12)t=12; printf \"%.1f\",t }")
    local color="white"
    (( wind_speed >= 40 )) && color="#ff0000" || { (( wind_speed >= 15 )) && color="#ffff00" || true; }

    printf '<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' > "$svg_path"
    printf '<defs><filter id="shadow"><feDropShadow dx="0" dy="1" stdDeviation="1" flood-opacity="0.5"/></filter></defs>' >> "$svg_path"
    printf '<g transform="translate(24,24) rotate(%d)" filter="url(#shadow)">' "$arrow_deg" >> "$svg_path"
    printf '<line x1="0" y1="12" x2="0" y2="-5" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' "$color" "$thick" >> "$svg_path"
    printf '<polygon points="0,-18 -12,-5 12,-5" fill="%s"/>' "$color" >> "$svg_path"
    printf '</g></svg>' >> "$svg_path"

    command -v rsvg-convert &>/dev/null && \
        rsvg-convert -w 48 -h 48 "$svg_path" -o "$png_path" 2>/dev/null || true

    cat > "$CACHE_PARSED" << EOF
temp=$temp
feels_like=$feels_like
temp_max=$temp_max
temp_min=$temp_min
humidity=$humidity
pressure=$pressure_inhg
wind_speed=$wind_speed
wind_deg=$wind_deg
wind_card=$wind_card
wind_unit=$wind_unit
temp_unit=$temp_unit
desc=$desc
icon_owm=$icon_code
icon_metno=$icon_metno
icon_uni=$icon_uni
wind_svg=$svg_path
sunrise=$sr_fmt
sunset=$ss_fmt
location=$loc
updated=$now_fmt
timestamp=$ts
EOF
}

# ── Background fetch worker ───────────────────────────────────────────────────

do_fetch_and_parse() {
    local url="https://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&units=${UNITS}&lang=${LANG}&appid=${OWM_API_KEY}"

    if ! curl -fsS --max-time 10 "$url" > "$TMP_JSON" 2>>"$LOG_FILE"; then
        sleep 3
        if ! curl -fsS --max-time 10 "$url" > "$TMP_JSON" 2>>"$LOG_FILE"; then
            echo "$(date -Is) WARN: fetch failed; keeping old cache" >> "$LOG_FILE"
            rm -f "$TMP_JSON"
            return 1
        fi
    fi

    if ! grep -q '"weather"' "$TMP_JSON"; then
        echo "$(date -Is) WARN: bad API response; keeping old cache" >> "$LOG_FILE"
        rm -f "$TMP_JSON"
        return 1
    fi

    mv -f "$TMP_JSON" "$CACHE_JSON"

    # Download OWM CDN icon for the returned code (always fetched; used as fallback for local too)
    local icon_code
    icon_code=$(jq -r '.weather[0].icon // empty' "$CACHE_JSON" 2>/dev/null || true)
    if [[ -n "$icon_code" ]]; then
        local icon_path="$ICON_DIR/${icon_code}.png"
        if [[ ! -f "$icon_path" || "$icon_path" -ot "$CACHE_JSON" ]]; then
            curl -fsS --max-time 8 \
                -o "$icon_path" \
                "https://openweathermap.org/img/wn/${icon_code}@2x.png" \
                2>>"$LOG_FILE" || true
        fi
    fi

    parse_and_write
    select_icon
}

# ── Main flow ─────────────────────────────────────────────────────────────────

# Always update icon (fast/synchronous — keeps icon correct across dawn/dusk)
select_icon

# If JSON exists but parsed file is missing, parse it now (no network needed).
# This covers the case where conky restarts while the cache is still fresh.
if [[ -f "$CACHE_JSON" && ! -f "$CACHE_PARSED" ]]; then
    parse_and_write
fi

# Exit immediately if cache is still fresh
is_cache_fresh && exit 0

# Atomic lock: if another fetch is already running, exit
mkdir "$LOCK_DIR" 2>/dev/null || exit 0

# Spawn background worker; lock is always released on exit
(
    trap 'rmdir "$LOCK_DIR" 2>/dev/null; exit' EXIT INT TERM
    do_fetch_and_parse
) &

exit 0
