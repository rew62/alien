#!/bin/bash
# fourmilab-earth.sh  2026-01-19  @rew62
# https://www.fourmilab.ch - Earth and Moon Viewer
# Dedicated to John Walker (2024) whose website made this script possible. Your voice remains in the code.
# 
# Place this line in your cron with crontab -e. Edit path to script location. Use full path. 
# */10 * * * * /home/<YOUR USER NAME>/.conky/alien/earth/fourmilab-earth.sh > /dev/shm/cron_debug.log 2>&1

# Configuration
NOW=$(date "+%Y-%m-%d %H:%M:%S")
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# File configuration
#Save Earth.png to SCRIPT_DIR or tempfs. /dev/shm is standard on Debian based systems including Ubuntu and Linux Mint.
OUTPUT_DIR="/dev/shm"              # or use $SCRIPT_DIR for persistent storage
FILENAME="earth"
FILE_EXT="png"                     # png or jpg

EARTH_IMG="$OUTPUT_DIR/$FILENAME.$FILE_EXT"
TEMP_FILE="$OUTPUT_DIR/$FILENAME.tmp.$FILE_EXT"
BACKUP_IMG="$SCRIPT_DIR/${FILENAME}_backup.$FILE_EXT"

THRESHOLD_MINS=9
WGET_TIMEOUT=30  # Seconds

# Multiple options available at https://www.fourmilab.ch/earthview/custom.html
URL="https://www.fourmilab.ch/cgi-bin/Earth?img=NASAmMM-l.evif&imgsize=600&dynimg=y&gamma=1.32&opt=-s&lat=&lon=&alt=&tle=&date=0&utc=&jd="

# 1. Check if file exists and is recent
if [ -f "$EARTH_IMG" ]; then
    FILE_TIME=$(stat -c %Y "$EARTH_IMG")
    CURRENT_TIME=$(date +%s)
    AGE=$((CURRENT_TIME - FILE_TIME))
    THRESHOLD_SECS=$((THRESHOLD_MINS * 60))
    if [ "$AGE" -lt "$THRESHOLD_SECS" ]; then
        echo "[$NOW] Image is $((AGE / 60)) minutes old. Skipping download."
        exit 0
    fi
fi

# 2. Download and Process
echo "[$NOW] Downloading and processing image..."
if wget --timeout="$WGET_TIMEOUT" --tries=2 -O - "$URL" | \
   convert - -fuzz 10% -transparent black -strip "$TEMP_FILE"; then
    if [ -s "$TEMP_FILE" ]; then
        mv "$TEMP_FILE" "$EARTH_IMG"
        # Save a backup copy to persistent storage
        cp "$EARTH_IMG" "$BACKUP_IMG"
        echo "[$NOW] Success: $EARTH_IMG updated."
    else
        echo "[$NOW] Error: Processed file is empty. Keeping existing image."
        [ -f "$TEMP_FILE" ] && rm "$TEMP_FILE"
        exit 1
    fi
else
    echo "[$NOW] Error: Download or ImageMagick processing failed. Keeping existing image."
    [ -f "$TEMP_FILE" ] && rm "$TEMP_FILE"
    
    # If no current image exists, restore from backup
    if [ ! -f "$EARTH_IMG" ] && [ -f "$BACKUP_IMG" ]; then
        echo "[$NOW] Restoring from backup image."
        cp -p "$BACKUP_IMG" "$EARTH_IMG"
    fi
    exit 1
fi
