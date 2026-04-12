-- hcal2.lua - Horizontal Lua/Cairo calendar script
-- v1.1 2026-04-09 @rew62
require 'cairo'

local M = {}

--------------------------------------------------
-- CONFIG
--------------------------------------------------
local FONT      = "MonaspiceNe Nerd Font Mono"
--local FONT      = "IBM Plex Mono"
local FONT_SIZE = 16      -- 12pt @ 96 DPI; adjust if calendar looks too big/small
local CELL_PAD  = 4       -- extra px between day columns; increase for more gap

local COL_TODAY   = { 0x39/255, 0xFF/255, 0x14/255, 1.0  }  -- neon green
local COL_WEEKEND = { 0xB8/255, 0xA8/255, 0xD0/255, 1.0  }  -- light purple
local COL_NAMES   = { 0x90/255, 0xA4/255, 0xAE/255, 1.0  }  -- blue-grey
local COL_DAY     = { 1.0,      1.0,      1.0,      0.90 }  -- white

local Y_NAMES = 65   -- baseline y for day-name row
local Y_NUMS  = 84   -- baseline y for day-number row  (adjust to match line height)
local X_OFFSET = 5   -- nudge calendar right (px) to clear left border

local material_months = {
    [1]  = "E57373", [2]  = "F06292", [3]  = "BA68C8",
    [4]  = "9575CD", [5]  = "7986CB", [6]  = "64B5F6",
    [7]  = "4DD0E1", [8]  = "4DB6AC", [9]  = "81C784",
    [10] = "AED581", [11] = "FFB74D", [12] = "A1887F"
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function set_color(cr, c)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
end

local function is_leap(y)
    if y % 400 == 0 then return true end
    if y % 100 == 0 then return false end
    if y % 4   == 0 then return true end
    return false
end

local function month_length(y, m)
    local d = {31,28,31,30,31,30,31,31,30,31,30,31}
    if m == 2 and is_leap(y) then return 29 end
    return d[m]
end

--------------------------------------------------
-- OWM DATA
--------------------------------------------------
local function read_sun_times()
    local file = io.open("/dev/shm/conky/owm_parsed.txt", "r")
    if not file then return nil, nil end
    local sunrise, sunset
    for line in file:lines() do
        local k, v = line:match("^(%w+)=(.+)$")
        if k == "sunrise" then sunrise = v end
        if k == "sunset"  then sunset  = v end
    end
    file:close()
    return sunrise, sunset
end

--------------------------------------------------
-- MOON PHASE (text output, for conky.text line)
--------------------------------------------------
local function moon_phase()
    local lp      = 2551443
    local now     = os.time()
    local new_moon = os.time{year=2001,month=1,day=24,hour=13,min=46}
    local phase   = ((now - new_moon) % lp) / lp
    local illumination = (1 - math.cos(phase * 2 * math.pi)) / 2 * 100

    -- 16 Nerd Font moon phase icons (Weather Icons set, confirmed in MonaspiceNe Nerd Font Mono)
    -- Waxing and waning share the crescent/gibbous icons (reversed for waning half).
    local NEW   = "\u{E3D5}"
    local CRES  = { "\u{E38E}", "\u{E38F}", "\u{E390}", "\u{E391}", "\u{E392}", "\u{E393}" }
    local FIRST = "\u{E394}"
    local GIB   = { "\u{E395}", "\u{E396}", "\u{E397}", "\u{E398}", "\u{E399}", "\u{E39A}" }
    local FULL  = "\u{E39B}"
    local LAST  = "\u{E3A2}"

    local name, symbol, color
    if phase < 0.02 or phase >= 0.98 then
        symbol, name, color = NEW, "New Moon", "546E7A"
    elseif phase < 0.23 then
        local i = math.min(math.floor((phase - 0.02) / 0.21 * 6) + 1, 6)
        symbol, name, color = CRES[i], "Waxing Crescent", "B0BEC5"
    elseif phase < 0.27 then
        symbol, name, color = FIRST, "First Quarter", "81D4FA"
    elseif phase < 0.48 then
        local i = math.min(math.floor((phase - 0.27) / 0.21 * 6) + 1, 6)
        symbol, name, color = GIB[i], "Waxing Gibbous", "E0E0E0"
    elseif phase < 0.52 then
        symbol, name, color = FULL, "Full Moon", "FFF59D"
    elseif phase < 0.73 then
        local i = math.min(math.floor((phase - 0.52) / 0.21 * 6) + 1, 6)
        symbol, name, color = GIB[7 - i], "Waning Gibbous", "E0E0E0"
    elseif phase < 0.77 then
        symbol, name, color = LAST, "Last Quarter", "81D4FA"
    else
        local i = math.min(math.floor((phase - 0.77) / 0.21 * 6) + 1, 6)
        symbol, name, color = CRES[7 - i], "Waning Crescent", "B0BEC5"
    end

    -- Symbol needs the Nerd Font; surrounding conky text may use a different font
    return string.format(
        "${font MonaspiceNe Nerd Font Mono:size=12}${color %s}%s${font}  ${color 90A4AE}%s  ${color 4DD0E1}(%.1f%%)",
        color, symbol, name, illumination
    )
end

--------------------------------------------------
-- CAIRO CALENDAR DRAW
--------------------------------------------------
function conky_draw_calendar()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)
    local cr = cairo_create(cs)

    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, FONT_SIZE)

    -- Measure one cell width using x_advance (exact for monospaced)
    local ext = cairo_text_extents_t:create()
    tolua.takeownership(ext)
    cairo_text_extents(cr, "00 ", ext)
    local cell_w = ext.x_advance + CELL_PAD

    -- Month data
    local now   = os.date("*t")
    local days  = month_length(now.year, now.month)
    local first = tonumber(os.date("%u", os.time{year=now.year, month=now.month, day=1}))
    local today = now.day
    local names = {"Mo","Tu","We","Th","Fr","Sa","Su"}

    -- Center the block
    local start_x = math.floor((conky_window.width - days * cell_w) / 2) + X_OFFSET

    -- Draw each day column
    local w = first
    for d = 1, days do
        local x          = start_x + (d - 1) * cell_w
        local is_weekend = (w >= 6)
        local is_today   = (d == today)

        -- Name row
        set_color(cr, is_weekend and COL_WEEKEND or COL_NAMES)
        cairo_move_to(cr, x, Y_NAMES)
        cairo_show_text(cr, names[w])

        -- Number row
        if is_today then
            set_color(cr, COL_TODAY)
        elseif is_weekend then
            set_color(cr, COL_WEEKEND)
        else
            set_color(cr, COL_DAY)
        end
        cairo_move_to(cr, x, Y_NUMS)
        cairo_show_text(cr, string.format("%02d", d))

        w = w + 1
        if w == 8 then w = 1 end
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

--------------------------------------------------
-- TEXT OUTPUT: moon + sun times only
--------------------------------------------------
--function conky_calendar_3mo_stacked()
function conky_info_row()
    local sunrise, sunset = read_sun_times()
    local sun_line
    if sunrise and sunset then
        sun_line = "${font MonaspiceNe Nerd Font Mono:size=24}${voffset -14}${color FFB74D}󰖜${font MonaspiceNe Nerd Font Mono:size=10}${voffset -6}${color FFECB3} " .. sunrise ..
        --sun_line = "${color FFB74D} ${color FFECB3}" .. sunrise ..
                   "${font DejaVu Sans:size=10}        " .. moon_phase() .. "      " ..
                   "${font MonaspiceNe Nerd Font Mono:size=10}${color FFAB91}" .. sunset .. " ${font MonaspiceNe Nerd Font Mono:size=24}${voffset -12}${color FF7043}󰖛 ${font}"
    else
        sun_line = moon_phase()
    end
    -- voffset pushes this line below the Cairo-drawn calendar rows
    --return "${voffset 38}${alignc}${font DejaVu Sans:size=10}" .. sun_line .. "\n"
    --return "${voffset 38}${goto 350}" .. sun_line .. "\n"
    return "${voffset 46}${goto 350}" .. sun_line 
end

return M
