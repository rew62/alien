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
    grep -roh '{font [^}]*}' "$SCRIPT_DIR" | \
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
echo "  - vnstat/vnstat.lua"
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

if [ -f "$SCRIPT_DIR/vnstat/vnstat.lua" ]; then
    sed -i 's/\(local[[:space:]]\+\)\?IFACE\([[:space:]]*=[[:space:]]*\)"[^"]*"/\1IFACE\2"'"$INTERFACE_NAME"'"/' "$SCRIPT_DIR/vnstat/vnstat.lua"
    echo -e "${GREEN}✓ Updated vnstat/vnstat.lua${NC}"
else
    echo -e "${YELLOW}⚠ File vnstat/vnstat.lua not found${NC}"
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
