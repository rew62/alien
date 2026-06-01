#!/bin/bash
# configure-alien.sh - Setup and configure the alien conky suite
# v1.1 2026-04-09 @rew62

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"
CRONTAB_FILE="$SCRIPT_DIR/earth/crontab"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Font check function ───────────────────────────────────────────────────
run_font_check() {
    echo
    echo -e "${BLUE}Checking fonts...${NC}"
    echo "================================"
    grep -roh --exclude-dir=.git -I '{font [^}]*}' "$SCRIPT_DIR" | \
        grep -o '{font [^:}]*' | \
        sed 's/{font //' | \
        grep -E '^[A-Za-z][A-Za-z0-9 ]+$' | \
        sort -u | \
        while read -r font; do
            if fc-list | grep -qiF "$font"; then
                echo -e "${GREEN}✓ $font${NC}"
            else
                echo -e "${YELLOW}✗ MISSING: $font${NC}"
            fi
        done
    echo
}

# ── Lyrics setup function ─────────────────────────────────────────────────
run_lyrics_check() {
    if [ -f "$SCRIPT_DIR/music/lyrics/setup.sh" ]; then
        echo
        read -p "Run lyrics dependency check? (yes/no): " RUN_LYRICS
        if [[ "$RUN_LYRICS" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
            echo -e "${BLUE}Running lyrics dependency check...${NC}"
            echo "================================"
            bash "$SCRIPT_DIR/music/lyrics/setup.sh"
        fi
    fi
}

# ── Function to get active internet-facing interface ─────────────────────
get_default_interface() {
    local iface=$(ip route | grep '^default' | head -n1 | awk '{print $5}')
    if [ -z "$iface" ]; then
        iface=$(ip link show | grep -E '^[0-9]+: (eth|wl|en)' | grep 'state UP' | head -n1 | awk -F': ' '{print $2}')
    fi
    echo "$iface"
}

# ── Geolocation helper ────────────────────────────────────────────────────
_geo_json_get() {
    local json="$1" key="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r "${key} // empty" 2>/dev/null
    else
        python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    keys = '${key}'.lstrip('.').split('.')
    v = d
    for k in keys:
        v = v[k]
    print(v if v is not None else '')
except Exception:
    pass
" <<< "$json" 2>/dev/null
    fi
}

# ── Geolocation function ──────────────────────────────────────────────────
run_geolocation() {
    echo -e "${BLUE}Detecting location...${NC}"
    local _lat="" _lon="" _source="" GEOCLUE_CMD=""

    for _path in "/usr/libexec/geoclue-2.0/demos/where-am-i" "/usr/lib/geoclue-2.0/demos/where-am-i" "/usr/bin/where-am-i"; do
        [[ -x "$_path" ]] && GEOCLUE_CMD="$_path" && break
    done

    if [[ -n "$GEOCLUE_CMD" ]]; then
        local _agent="/usr/lib/geoclue-2.0/demos/agent"
        if [[ -x "$_agent" ]] && ! pgrep -f "$_agent" >/dev/null; then
            "$_agent" &>/dev/null &
            disown
        fi
        local _gc_data
        _gc_data=$(timeout 3s "$GEOCLUE_CMD" --timeout=2 2>/dev/null) || _gc_data=""
        if [[ -n "$_gc_data" ]]; then
            _lat=$(echo "$_gc_data" | grep "Latitude:"  | cut -d: -f2 | tr -d '[:space:]' | sed 's/[^0-9.-]//g')
            _lon=$(echo "$_gc_data" | grep "Longitude:" | cut -d: -f2 | tr -d '[:space:]' | sed 's/[^0-9.-]//g' | sed 's/\.$//')
            _source="geoclue"
        fi
    fi

    if [[ -z "$_lat" || "$_lat" == "null" ]] && command -v python3 &>/dev/null; then
        local _py_data
        _py_data=$(python3 - 2>/dev/null <<'PYEOF'
import gi, sys
try:
    gi.require_version('Geoclue', '2.0')
    from gi.repository import Geoclue
    client = Geoclue.Simple.new_sync('get-location', Geoclue.AccuracyLevel.EXACT, None)
    loc = client.get_location()
    print(loc.get_property('latitude'))
    print(loc.get_property('longitude'))
except Exception:
    sys.exit(1)
PYEOF
) || _py_data=""
        if [[ -n "$_py_data" ]]; then
            _lat=$(echo "$_py_data" | sed -n '1p')
            _lon=$(echo "$_py_data" | sed -n '2p')
            _source="geoclue-dbus"
        fi
    fi

    if [[ -z "$_lat" || "$_lat" == "null" ]]; then
        local _providers=(
            "https://ipapi.co/json|.latitude|.longitude"
            "https://freeipapi.com/api/json|.latitude|.longitude"
            "http://ip-api.com/json|.lat|.lon"
            "https://ipinfo.io/json|.loc|"
        )
        local _purl _lpath _lonpath _gdata _loc
        for _pentry in "${_providers[@]}"; do
            IFS='|' read -r _purl _lpath _lonpath <<< "$_pentry"
            _gdata=$(curl -s --max-time 5 -k "$_purl" 2>/dev/null || wget -qO- -T 5 --no-check-certificate "$_purl" 2>/dev/null) || _gdata=""
            [[ -z "$_gdata" ]] && continue
            if [[ "$_lpath" == ".loc" ]]; then
                _loc=$(_geo_json_get "$_gdata" ".loc") || _loc=""
                if [[ "$_loc" =~ ^(-?[0-9]+\.?[0-9]*),(-?[0-9]+\.?[0-9]*)$ ]]; then
                    _lat="${BASH_REMATCH[1]}"
                    _lon="${BASH_REMATCH[2]}"
                fi
            else
                _lat=$(_geo_json_get "$_gdata" "$_lpath") || _lat=""
                _lon=$(_geo_json_get "$_gdata" "$_lonpath") || _lon=""
            fi
            if [[ -n "$_lat" && "$_lat" != "null" && "$_lat" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                _source="$_purl"
                break
            else
                _lat="" _lon=""
            fi
        done
    fi

    if [[ -n "$_lat" && "$_lat" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        LAT="$_lat"
        LON="$_lon"
        echo -e "${GREEN}✓ Location detected: $LAT, $LON (via $_source)${NC}"
    else
        echo -e "${YELLOW}⚠ Could not determine location automatically.${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}Configuration Script${NC}"
echo "================================"
echo
echo -e "${YELLOW}NOTE: This script will update configuration files as needed.${NC}"
echo -e "${YELLOW}Required keys: OWM_API_KEY, CITY_ID, UNITS, LAT, LON${NC}"
if [ -f "$ENV_EXAMPLE" ]; then
    echo -e "${YELLOW}See .env.example for the format reference.${NC}"
fi
echo

# ── Load and display existing .env if present ────────────────────────────
OWM_API_KEY=""; CITY_ID=""; UNITS=""; LAT=""; LON=""; INTERFACE_NAME=""; CRONPATH=""; FINNHUB_API_KEY=""
LANG=""; ICON_SOURCE=""; CACHE_TTL=""

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    if [ -z "$INTERFACE_NAME" ] || ! ip link show "$INTERFACE_NAME" up &>/dev/null 2>&1; then
        INTERFACE_NAME=$(get_default_interface)
    fi
    [ -z "$CRONPATH" ]       && CRONPATH="$USER"

    echo -e "${YELLOW}Current configuration:${NC}"
    printf "  %-15s %s\n" "OWM API Key:"     "$OWM_API_KEY"
    printf "  %-15s %s\n" "FinnHub Key:"     "$FINNHUB_API_KEY"
    printf "  %-15s %s\n" "City ID:"         "$CITY_ID"
    printf "  %-15s %s\n" "Latitude:"        "$LAT"
    printf "  %-15s %s\n" "Longitude:"       "$LON"
    printf "  %-15s %s\n" "Temp Unit:"       "$UNITS"
    printf "  %-15s %s\n" "Language:"        "$LANG"
    printf "  %-15s %s\n" "Icon Source:"     "$ICON_SOURCE"
    printf "  %-15s %s\n" "Cache TTL:"       "$CACHE_TTL"
    printf "  %-15s %s\n" "Interface:"       "$INTERFACE_NAME"
    printf "  %-15s %s\n" "Cron User:"       "$CRONPATH"
    echo

    read -p "Any changes needed? (yes/no): " HAS_CHANGES
    if [[ ! "$HAS_CHANGES" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        echo -e "${GREEN}No changes. Nothing to update.${NC}"
        run_font_check
        run_lyrics_check
        exit 0
    fi
    echo
else
    # First run — no .env yet, set defaults
    INTERFACE_NAME=$(get_default_interface)
    CRONPATH="$USER"
    echo -e "${YELLOW}No existing configuration found. Please enter your settings.${NC}"
    echo
fi

# ── Geolocation prompt ────────────────────────────────────────────────────
read -p "Identify current location? (yes/no): " GET_LOC
if [[ "$GET_LOC" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    run_geolocation
    echo
fi

# ── Individual prompts ────────────────────────────────────────────────────
read -p "OWM API Key [$OWM_API_KEY]: " INPUT
OWM_API_KEY=${INPUT:-$OWM_API_KEY}

read -p "FinnHub API Key [$FINNHUB_API_KEY]: " INPUT
FINNHUB_API_KEY=${INPUT:-$FINNHUB_API_KEY}

read -p "City ID [$CITY_ID]: " INPUT
CITY_ID=${INPUT:-$CITY_ID}

read -p "metric (Celsius) or imperial (Fahrenheit) [$UNITS]: " INPUT
UNITS=${INPUT:-$UNITS}

read -p "Language code (e.g. en, fr, de) [$LANG]: " INPUT
LANG=${INPUT:-${LANG:-en}}

read -p "Icon source (cdn or local) [$ICON_SOURCE]: " INPUT
ICON_SOURCE=${INPUT:-${ICON_SOURCE:-cdn}}

read -p "Cache TTL in seconds [$CACHE_TTL]: " INPUT
CACHE_TTL=${INPUT:-${CACHE_TTL:-300}}

read -p "Latitude [$LAT]: " INPUT
LAT=${INPUT:-$LAT}

read -p "Longitude [$LON]: " INPUT
LON=${INPUT:-$LON}

read -p "Network interface [$INTERFACE_NAME]: " INPUT
INTERFACE_NAME=${INPUT:-$INTERFACE_NAME}

read -p "Cron User [$CRONPATH]: " INPUT
CRONPATH=${INPUT:-$CRONPATH}

echo
echo -e "${GREEN}Updated configuration:${NC}"
printf "  %-30s %s\n" "OWM API Key:"    "$OWM_API_KEY"
printf "  %-30s %s\n" "FinnHub API Key:" "$FINNHUB_API_KEY"
printf "  %-30s %s\n" "City ID:"    "$CITY_ID"
printf "  %-30s %s\n" "Temp Unit:"      "$UNITS"
printf "  %-30s %s\n" "Language:"       "$LANG"
printf "  %-30s %s\n" "Icon Source:"    "$ICON_SOURCE"
printf "  %-30s %s\n" "Cache TTL:"      "$CACHE_TTL"
printf "  %-30s %s\n" "Latitude:"       "$LAT"
printf "  %-30s %s\n" "Longitude:"      "$LON"
printf "  %-30s %s\n" "Interface:"      "$INTERFACE_NAME"
printf "  %-30s %s\n" "Cron User:"      "$CRONPATH"
echo

# ── Files to be updated ───────────────────────────────────────────────────
echo "Files to be updated:"
echo "  - $ENV_FILE"
echo "  - calendar/sys-small.rc"
echo "  - calendar/sys-small2.rc"
echo "  - vnstat/settings.lua"
echo "  - vnstat/net.rc"
#echo "  - network/network.rc"
#echo "  - network/settings.lua"
if [ -f "$CRONTAB_FILE" ]; then
    echo "  - $CRONTAB_FILE"
fi
echo

read -p "Proceed with updates? (yes/no): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    echo "Configuration cancelled. No files were modified."
    run_font_check
    run_lyrics_check
    exit 0
fi

# ── Write .env ────────────────────────────────────────────────────────────
cat > "$ENV_FILE" << EOF
OWM_API_KEY="$OWM_API_KEY"
FINNHUB_API_KEY="$FINNHUB_API_KEY"
CITY_ID="$CITY_ID"
UNITS="$UNITS"
LANG="$LANG"
ICON_SOURCE="$ICON_SOURCE"
CACHE_TTL="$CACHE_TTL"
LAT=$LAT
LON=$LON
INTERFACE_NAME="$INTERFACE_NAME"
CRONPATH="$CRONPATH"
EOF
chmod 600 "$ENV_FILE"
echo -e "${GREEN}✓ Saved $ENV_FILE (permissions: 600)${NC}"

# ── Update interface files ────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/calendar/sys-small.rc" ]; then
    sed -i "s/template1[[:space:]]*=[[:space:]]*\"[^\"]*\"/template1          = \"$INTERFACE_NAME\"/" "$SCRIPT_DIR/calendar/sys-small.rc"
    echo -e "${GREEN}✓ Updated calendar/sys-small.rc${NC}"
else
    echo -e "${YELLOW}⚠ File calendar/sys-small.rc not found${NC}"
fi

if [ -f "$SCRIPT_DIR/calendar/sys-small2.rc" ]; then
    sed -i "s/template1[[:space:]]*=[[:space:]]*\"[^\"]*\"/template1          = \"$INTERFACE_NAME\"/" "$SCRIPT_DIR/calendar/sys-small2.rc"
    echo -e "${GREEN}✓ Updated calendar/sys-small2.rc${NC}"
else
    echo -e "${YELLOW}⚠ File calendar/sys-small2.rc not found${NC}"
fi

if [ -f "$SCRIPT_DIR/vnstat/settings.lua" ]; then
    sed -i 's/var_NETWORK[[:space:]]*=[[:space:]]*"[^"]*"/var_NETWORK = "'"$INTERFACE_NAME"'"/' "$SCRIPT_DIR/vnstat/settings.lua"
    echo -e "${GREEN}✓ Updated vnstat/settings.lua${NC}"
else
    echo -e "${YELLOW}⚠ File vnstat/settings.lua not found${NC}"
fi

if [ -f "$SCRIPT_DIR/vnstat/net.rc" ]; then
    sed -i "s/template1[[:space:]]*=[[:space:]]*\"[^\"]*\"/template1 = \"$INTERFACE_NAME\"/" "$SCRIPT_DIR/vnstat/net.rc"
    echo -e "${GREEN}✓ Updated vnstat/net.rc${NC}"
else
    echo -e "${YELLOW}⚠ File vnstat/net.rc not found${NC}"
fi

# ── Update crontab ────────────────────────────────────────────────────────
if [ -f "$CRONTAB_FILE" ]; then
    sed -i "s|/home/<user>/|/home/$CRONPATH/|g" "$CRONTAB_FILE"
    echo -e "${GREEN}✓ Updated $CRONTAB_FILE${NC}"
fi

echo
echo -e "${GREEN}Configuration complete!${NC}"

# ── Font check ────────────────────────────────────────────────────────────
run_font_check
