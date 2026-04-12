#!/usr/bin/env bash
# rss-fetch.sh - Fetch RSS feeds and cache to /dev/shm/rss
#
# v1.1 2026-04-09 @rew62

DIR="$(cd "$(dirname "$0")"; pwd)"
FEEDS="$DIR/feeds.conf"
CACHE_DIR="/dev/shm/rss"
IDX_FILE="$CACHE_DIR/feed_idx"
OUT_TXT="$CACHE_DIR/rss.txt"
OUT_MAP="$CACHE_DIR/rss.map"
TMP_XML="$CACHE_DIR/rss.xml"

MAX_ITEMS=8

mkdir -p "$CACHE_DIR"

# read current feed index (1-based), default to 1
TOTAL=$(grep -vc '^\s*#\|^\s*$' "$FEEDS")
IDX=$(cat "$IDX_FILE" 2>/dev/null || echo 1)
IDX=$(( (IDX - 1) % TOTAL + 1 ))

FEED_NAME=$(grep -v '^\s*#\|^\s*$' "$FEEDS" | awk -F'|' -v i="$IDX" 'NR==i {print $1}')
FEED_URL=$(grep -v '^\s*#\|^\s*$' "$FEEDS" | awk -F'|'  -v i="$IDX" 'NR==i {print $2}')

# fetch XML
curl -sL "$FEED_URL" -o "$TMP_XML"

# parse XML and validate in one pass
ITEMS=$(python3 - "$TMP_XML" "$MAX_ITEMS" <<'PYEOF'
import sys, xml.etree.ElementTree as ET

xml_file, max_items = sys.argv[1], int(sys.argv[2])
try:
    root = ET.parse(xml_file).getroot()
except Exception:
    sys.exit(1)

ns = {'atom': 'http://www.w3.org/2005/Atom'}
items = root.findall('.//item') or root.findall('.//atom:entry', ns)
if not items:
    sys.exit(1)

for item in items[:max_items]:
    title = (item.findtext('title') or item.findtext('atom:title', namespaces=ns) or '').strip()
    link  = (item.findtext('link')  or item.findtext('atom:link',  namespaces=ns) or '').strip()
    # atom:link is often an element with href, not text
    if not link:
        el = item.find('atom:link', ns)
        link = (el.get('href') or '') if el is not None else ''
    print(f'{title}|{link}')
PYEOF
)

if [ -z "$ITEMS" ]; then
    echo "Feed error" > "$OUT_TXT"
    exit 1
fi

# build output + map
: > "$OUT_TXT"
: > "$OUT_MAP"

# index 1 = feed name header (clicking cycles to next feed)
echo "\${font MonaspiceNe Nerd Font Mono:size=10}\${color green}▶▶  \${font}\${color}$FEED_NAME" >> "$OUT_TXT"
echo "1|next" >> "$OUT_MAP"

# headlines at index 2+
echo "$ITEMS" \
| nl -w1 -s'|' -v2 \
| while IFS='|' read -r idx title link; do
    echo "• ${title//$/$$}" >> "$OUT_TXT"
    echo "$idx|$link" >> "$OUT_MAP"
done
