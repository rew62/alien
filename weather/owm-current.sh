#!/usr/bin/env bash
# owm-current.sh - Read owm_parsed.txt and print a single field value
# Zero logic, zero parsing — grep/cut one-liner per field
# v1.1 2026-04-09 @rew62
# Usage:  owm-current.sh <field>
#
# Fields:
#   temp          current temperature
#   feels_like    feels like temperature
#   temp_max      daily high (OWM)
#   temp_min      daily low  (OWM)
#   humidity      humidity %
#   pressure      barometric pressure (inHg)
#   wind_speed    wind speed
#   wind_deg      wind direction degrees
#   wind_card     wind direction cardinal (NNW, SW, etc.)
#   wind_unit     mph or kph
#   temp_unit     °F or °C
#   desc          weather description (Title Case)
#   icon_owm      OWM icon code  (e.g. 01d)
#   icon_metno    MET Norway icon name (e.g. clearsky_day)
#   icon_uni      Unicode weather glyph (e.g. ☀)
#   wind_svg      path to current wind arrow SVG
#   sunrise       sunrise time (12h)
#   sunset        sunset time  (12h)
#   location      city name from OWM
#   updated       last fetch time (12h)
#   timestamp     Unix timestamp of last fetch
#   all           print every key=value line (debug)

CACHE="/dev/shm/conky/owm_parsed.txt"
FIELD="${1:-temp}"

if [[ ! -f "$CACHE" ]]; then
    echo "N/A"
    exit 0
fi

if [[ "$FIELD" == "all" ]]; then
    cat "$CACHE"
    exit 0
fi

grep "^${FIELD}=" "$CACHE" | cut -d= -f2-
