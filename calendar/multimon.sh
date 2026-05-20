#!/bin/bash
# Multi-month Calendar for Conky
# v1.1 2026-05-19 @rew62

NUM_MONTHS=4
START_MONTH=-1  # month offset from current: 0=this month, -1=last month, 1=next month
START_DOW=0     # 0=Sunday, 1=Monday, ..., 6=Saturday
MONTH_GAP=4     # pixels of space between month title and weekday header

COL_TITLE=ffffff   # month title
COL_DAYS=76898F    # normal day numbers
WEEKEND_DIM=30     # how much darker weekend days are than COL_DAYS (0-255)
#COL_WEEKEND=6E8187 # override: set a fixed hex color instead of deriving
COL_TODAY=E8A060   # today's date
#COL_SUNDAY=cf5160  # Sunday header label
COL_SUNDAY=ffffff  # Sunday header label

CURR_MONTH=$(date +%-m)
CURR_YEAR=$(date +%-Y)
TODAY=$(date +%-d)

NAMES=("Su" "Mo" "Tu" "We" "Th" "Fr" "Sa")

days_in_month() {
    date -d "$2-$1-01 +1 month -1 day" +%-d
}

# Returns 1-based column for the first day of the month under the configured week start
first_col() {
    local dow
    dow=$(date -d "$2-$1-01" +%w)   # %w: 0=Sun ... 6=Sat
    echo $(( (dow - START_DOW + 7) % 7 + 1 ))
}

# Derive COL_WEEKEND from COL_DAYS unless manually overridden above
if [ -z "$COL_WEEKEND" ]; then
    _r=$(( 16#${COL_DAYS:0:2} - WEEKEND_DIM ))
    _g=$(( 16#${COL_DAYS:2:2} - WEEKEND_DIM ))
    _b=$(( 16#${COL_DAYS:4:2} - WEEKEND_DIM ))
    COL_WEEKEND=$(printf '%02X%02X%02X' $((_r<0?0:_r)) $((_g<0?0:_g)) $((_b<0?0:_b)))
fi

# Precompute which columns (1-7) fall on Saturday and Sunday
SAT_COL=$(( (6 - START_DOW + 7) % 7 + 1 ))
SUN_COL=$(( (0 - START_DOW + 7) % 7 + 1 ))

# Build weekday header once — Sunday always gets red highlight
HEADER=''
for ((h=0; h<7; h++)); do
    idx=$(( (START_DOW + h) % 7 ))
    if [ $idx -eq 0 ]; then
        HEADER="${HEADER}\${color $COL_SUNDAY} ${NAMES[$idx]}\${color}"
    else
        HEADER="${HEADER} ${NAMES[$idx]}"
    fi
done

for ((i=0; i<NUM_MONTHS; i++)); do
    total=$((CURR_YEAR * 12 + CURR_MONTH - 1 + START_MONTH + i))
    y=$((total / 12))
    m=$((total % 12 + 1))

    MONTH_NAME=$(date -d "$y-$m-01" +"%B %Y")
    NUM_DAYS=$(days_in_month $m $y)
    FIRST_COL=$(first_col $m $y)

    # Month title
    echo "\${font mono:bold:size=12}\${color $COL_TITLE}$MONTH_NAME"

    # Weekday header
    echo '${voffset '"$MONTH_GAP"'}''${font mono:size=12}''${color}'"$HEADER"

    # Day rows
    COL=$FIRST_COL
    LINE='${font mono:size=12}'

    # Leading blank cells so day 1 lands on the correct column
    for ((pad=1; pad<FIRST_COL; pad++)); do
        LINE="$LINE   "
    done

    for ((d=1; d<=NUM_DAYS; d++)); do
        if [ $m -eq $CURR_MONTH ] && [ $y -eq $CURR_YEAR ] && [ $d -eq $TODAY ]; then
            DAY_COL="\${color $COL_TODAY}"
        elif [ $COL -eq $SAT_COL ] || [ $COL -eq $SUN_COL ]; then
            DAY_COL="\${color $COL_WEEKEND}"
        else
            DAY_COL="\${color $COL_DAYS}"
        fi

        if [ $d -lt 10 ]; then
            LINE="${LINE}${DAY_COL} 0${d}"
        else
            LINE="${LINE}${DAY_COL} ${d}"
        fi

        if [ $COL -eq 7 ] && [ $d -ne $NUM_DAYS ]; then
            echo "$LINE"
            LINE='${font mono:size=12}'
            COL=0
        fi

        COL=$((COL + 1))
    done
    echo "$LINE"

    # Blank spacer between months
    if [ $i -lt $((NUM_MONTHS - 1)) ]; then
        echo ''
    fi
done
