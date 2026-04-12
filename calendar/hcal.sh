#!/bin/bash
# hcal.sh - Display horizontal calendar on conky with unicode box drawing
# v1.2 2026-01-19 @rew62

TODAY=$(date +%d)
TOPLINE=" "
OVER=" "
REST=" "

# -------- Find the number of days in the month (Variable 'b') -----------#
a=$(date +%-Y)
e1=$((a % 400))
e2=$((a % 100))
e3=$((a % 4))
if [ "$e1" -eq 0 ]; then
    c=1
elif [ "$e2" -eq 0 ]; then
    c=0
elif [ "$e3" -eq 0 ]; then
    c=1
else
    c=0
fi
p=$(date +%-m)

# Determine the length of the current month ('b')
if [ "$c" -eq 0 ]; then # Not a leap year
    if [ "$p" -eq 2 ]; then
        b=28
    elif [ "$p" -eq 11 ] || [ "$p" -eq 4 ] || [ "$p" -eq 6 ] || [ "$p" -eq 9 ]; then
        b=30
    else
        b=31
    fi
else # Leap year
    if [ "$p" -eq 2 ]; then
        b=29
    elif [ "$p" -eq 11 ] || [ "$p" -eq 4 ] || [ "$p" -eq 6 ] || [ "$p" -eq 9 ]; then
        b=30
    else
        b=31
    fi
fi

#--------------------- Bottom line: Days of the month ----------#
i=1
# Days before today
if [ "$TODAY" -ne 1 ]; then
    while [ "$i" -lt "$TODAY" ]; do
        if [ "$i" -lt 10 ]; then
            OVER="$OVER 0$i"
        else
            OVER="$OVER $i"
        fi
        i=$((i+1))
    done
fi
i=$((i+1))
# Days after today
if [ "$TODAY" -ne "$b" ]; then
    while [ "$i" -le "$b" ]; do 
        if [ "$i" -lt 10 ]; then
            REST="$REST 0$i"
        else
            REST="$REST $i"
        fi
        i=$((i+1))
    done
fi

#------------- Top line: Abbreviated weekday names (Mo, Tu, etc.) -------#
FIRST_DAY_OF_MONTH_INDEX=$(date +%u --date="$(date +%Y-%m-01)")
y=$FIRST_DAY_OF_MONTH_INDEX
month_length=$b

while [ "$month_length" -gt 0 ]; do
    case "$y" in
    1) TOPLINE="$TOPLINE Mo";;
    2) TOPLINE="$TOPLINE Tu";;
    3) TOPLINE="$TOPLINE We";;
    4) TOPLINE="$TOPLINE Th";;
    5) TOPLINE="$TOPLINE Fr";;
    6) TOPLINE="$TOPLINE Sa";;
    7) TOPLINE="$TOPLINE Su";;
    esac
    
    month_length=$((month_length-1))
    y=$((y+1))
    if [ "$y" -eq 8 ]; then
        y=1
    fi
done

# --- Build output with colors ---
TOP_OUTPUT=$(echo "${TOPLINE}" | sed 's/Su/${color1}Su${color}/g' | sed 's/Sa/${color1}Sa${color}/g')
#BOTTOM_OUTPUT='${color C28C3A}'"$OVER"'${color 5BED1B}'" $TODAY"'${color}'${REST:1}
BOTTOM_OUTPUT="$OVER"'${color 5BED1B}'" $TODAY"'${color}'${REST:1}

# Calculate box width based on actual visible content (not including color codes)
CONTENT_WIDTH=$((b * 3 + 2))  # Each day takes 3 chars, plus initial space

# Create horizontal line
HLINE=$(printf '─%.0s' $(seq 1 $CONTENT_WIDTH))

# Output with unicode box
#echo '${font Ubuntu Mono:Bold:size=10}'"┌${HLINE}┐"
#echo "┌${HLINE}┐"
#echo "│${TOP_OUTPUT} │"
#echo "│${BOTTOM_OUTPUT} │"
#echo "└${HLINE}┘"
echo "${TOP_OUTPUT}"
echo "${BOTTOM_OUTPUT} "
