-- hcal2.lua - Horizontal Lua/Cairo calendar with zodiac sign
-- v1.2 2026-05-18 @rew62

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
local COL_WEEKEND = { 0xD0/255, 0xB8/255, 0xE8/255, 1.0  }  -- light purple
local COL_GREEN   = { 0x98/255, 0xFB/255, 0x98/255, 1.0  }  -- pale green
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
-- ZODIAC
--------------------------------------------------
local zodiac = {
    { sym = "♑", name = "Capricorn",   start_d = 22, start_m = 12, end_d = 19, end_m =  1 },
    { sym = "♒", name = "Aquarius",    start_d = 20, start_m =  1, end_d = 18, end_m =  2 },
    { sym = "♓", name = "Pisces",      start_d = 19, start_m =  2, end_d = 20, end_m =  3 },
    { sym = "♈", name = "Aries",       start_d = 21, start_m =  3, end_d = 19, end_m =  4 },
    { sym = "♉", name = "Taurus",      start_d = 20, start_m =  4, end_d = 20, end_m =  5 },
    { sym = "♊", name = "Gemini",      start_d = 21, start_m =  5, end_d = 20, end_m =  6 },
    { sym = "♋", name = "Cancer",      start_d = 21, start_m =  6, end_d = 22, end_m =  7 },
    { sym = "♌", name = "Leo",         start_d = 23, start_m =  7, end_d = 22, end_m =  8 },
    { sym = "♍", name = "Virgo",       start_d = 23, start_m =  8, end_d = 22, end_m =  9 },
    { sym = "♎", name = "Libra",       start_d = 23, start_m =  9, end_d = 22, end_m = 10 },
    { sym = "♏", name = "Scorpio",     start_d = 23, start_m = 10, end_d = 21, end_m = 11 },
    { sym = "♐", name = "Sagittarius", start_d = 22, start_m = 11, end_d = 21, end_m = 12 },
}

local function current_sign()
    local day   = tonumber(os.date("%d"))
    local month = tonumber(os.date("%m"))
    for _, z in ipairs(zodiac) do
        if (month == z.start_m and day >= z.start_d) or
           (month == z.end_m   and day <= z.end_d) then
            return z
        end
    end
end

function conky_get_zodiac_sym()
    local z = current_sign()
    return z and z.sym or "?"
end

function conky_get_zodiac_name()
    local z = current_sign()
    return z and z.name or "?"
end

function conky_get_zodiac_right()
    local z = current_sign()
    return z and (z.sym .. "  " .. z.name) or "?"
end

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
        local is_weekend = (w == 7)
        local is_today   = (d == today)

        -- Name row
        set_color(cr, is_weekend and COL_GREEN or COL_NAMES)
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
-- CENTER HEADER: w: <week>  Month Year  d: <day>
--------------------------------------------------
local Y_CTR_MAIN   = 37   -- Month Year baseline; tune to match old ${alignc} line
local Y_CTR_FLANKS = 29   -- w:/d: baseline; tune for optical alignment with main
local CTR_GAP      = 100  -- px gap between flanks and Month Year edges
local CTR_MAIN_PX  = 24   -- ~22pt @ 96dpi
local CTR_FLANK_PX = 13   -- ~10pt @ 96dpi

function conky_draw_center_header()
    if conky_window == nil then return end

    local month_yr = os.date("%B %Y")
    local week_str = "w: " .. tostring(tonumber(os.date("%V")))
    local day_str  = "d: " .. tostring(tonumber(os.date("%j")))

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)
    local cr = cairo_create(cs)

    -- Measure Month Year
    cairo_select_font_face(cr, "Orbitron", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, CTR_MAIN_PX)
    local me = cairo_text_extents_t:create()
    tolua.takeownership(me)
    cairo_text_extents(cr, month_yr, me)

    -- Measure week string
    cairo_select_font_face(cr, "Orbitron", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, CTR_FLANK_PX)
    local we = cairo_text_extents_t:create()
    tolua.takeownership(we)
    cairo_text_extents(cr, week_str, we)

    -- X positions: Month Year centered, flanks at ±CTR_GAP from its edges
    local main_x  = math.floor(conky_window.width / 2 - me.x_advance / 2)
    local week_x  = main_x - CTR_GAP - we.x_advance
    local day_x   = main_x + me.x_advance + CTR_GAP

    -- Month Year (PaleGreen)
    cairo_set_source_rgba(cr, 0x98/255, 0xFB/255, 0x98/255, 1.0)
    cairo_select_font_face(cr, "Orbitron", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, CTR_MAIN_PX)
    cairo_move_to(cr, main_x, Y_CTR_MAIN)
    cairo_show_text(cr, month_yr)

    -- w: and d: (light purple)
    cairo_set_source_rgba(cr, 0xD0/255, 0xB8/255, 0xE8/255, 1.0)
    cairo_select_font_face(cr, "Orbitron", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, CTR_FLANK_PX)
    cairo_move_to(cr, week_x, Y_CTR_FLANKS)
    cairo_show_text(cr, week_str)
    cairo_move_to(cr, day_x, Y_CTR_FLANKS)
    cairo_show_text(cr, day_str)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

--------------------------------------------------
-- HEADER ZODIAC (Cairo, right-aligned)
--------------------------------------------------
local HDR_GLYPH_FONT = "DejaVu Sans Mono"
local HDR_GLYPH_PX   = 29      -- ~22pt @ 96 dpi; tune to taste
local HDR_NAME_FONT  = "Orbitron"
local HDR_NAME_PX    = 13      -- ~10pt @ 96 dpi; tune to match line-1 text
local HDR_R_MARGIN   = 10      -- px from right window edge
local HDR_GAP        =  6      -- px between glyph and name
local Y_HDR_GLYPH    = 34      -- glyph baseline; increase if it clips at top
local Y_HDR_NAME     = 30      -- name baseline; tune to align with left date

function conky_draw_zodiac_header()
    if conky_window == nil then return "" end
    local z = current_sign()
    if not z then return "" end

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)
    local cr = cairo_create(cs)

    -- Measure name width
    cairo_select_font_face(cr, HDR_NAME_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, HDR_NAME_PX)
    local ne = cairo_text_extents_t:create()
    tolua.takeownership(ne)
    cairo_text_extents(cr, z.name, ne)

    -- Measure glyph width
    cairo_select_font_face(cr, HDR_GLYPH_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, HDR_GLYPH_PX)
    local ge = cairo_text_extents_t:create()
    tolua.takeownership(ge)
    cairo_text_extents(cr, z.sym, ge)

    -- Positions: name flush to right margin, glyph left of name
    local name_x  = conky_window.width - HDR_R_MARGIN - ne.x_advance
    local glyph_x = name_x - HDR_GAP - ge.x_advance

    cairo_set_source_rgba(cr, 0xD0/255, 0xB8/255, 0xE8/255, 1.0)

    cairo_select_font_face(cr, HDR_GLYPH_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, HDR_GLYPH_PX)
    cairo_move_to(cr, glyph_x, Y_HDR_GLYPH)
    cairo_show_text(cr, z.sym)

    cairo_select_font_face(cr, HDR_NAME_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, HDR_NAME_PX)
    cairo_move_to(cr, name_x, Y_HDR_NAME)
    cairo_show_text(cr, z.name)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    return ""
end

--------------------------------------------------
-- COMBINED HEADER (single Cairo context, all 3 lines)
--------------------------------------------------
function conky_draw_header()
    if conky_window == nil then return end
    local z        = current_sign()
    local now      = os.date("*t")
    local week     = tostring(tonumber(os.date("%V")))
    local day      = tostring(tonumber(os.date("%j")))
    local date_p1  = os.date("%A, %B ") .. now.day .. ", " .. now.year
    local date_p2  = "w: " .. week
    local date_p3  = "d: " .. day
    local month_yr = os.date("%B %Y")

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)
    local cr = cairo_create(cs)

    -- Measure all strings
    cairo_select_font_face(cr, HDR_NAME_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)

    cairo_set_font_size(cr, HDR_NAME_PX)
    local p1e = cairo_text_extents_t:create() ; tolua.takeownership(p1e)
    cairo_text_extents(cr, date_p1, p1e)
    local p2e = cairo_text_extents_t:create() ; tolua.takeownership(p2e)
    cairo_text_extents(cr, date_p2, p2e)
    local ne = cairo_text_extents_t:create() ; tolua.takeownership(ne)
    cairo_text_extents(cr, z and z.name or "", ne)

    cairo_set_font_size(cr, CTR_MAIN_PX)
    local me = cairo_text_extents_t:create() ; tolua.takeownership(me)
    cairo_text_extents(cr, month_yr, me)

    cairo_select_font_face(cr, HDR_GLYPH_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, HDR_GLYPH_PX)
    local ge = cairo_text_extents_t:create() ; tolua.takeownership(ge)
    cairo_text_extents(cr, z and z.sym or "", ge)

    -- X positions
    local main_x   = math.floor(conky_window.width / 2 - me.x_advance / 2)
    local zname_x  = conky_window.width - HDR_R_MARGIN - ne.x_advance
    local zglyph_x = zname_x - HDR_GAP - ge.x_advance

    local purple = COL_WEEKEND
    local green  = { 0x98/255, 0xFB/255, 0x98/255, 1.0 }

    -- Line 1: left date with vertical dividers
    local DIV_PAD = 8   -- px on each side of divider line
    local DIV_H   = 11  -- divider line height in px
    local div_y   = Y_HDR_NAME - DIV_H + 2
    cairo_set_source_rgba(cr, purple[1], purple[2], purple[3], purple[4])
    cairo_select_font_face(cr, HDR_NAME_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, HDR_NAME_PX)
    local lx = 10
    cairo_move_to(cr, lx, Y_HDR_NAME)
    cairo_show_text(cr, date_p1)
    lx = lx + p1e.x_advance + DIV_PAD
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, lx, div_y) ; cairo_line_to(cr, lx, div_y + DIV_H) ; cairo_stroke(cr)
    lx = lx + DIV_PAD
    cairo_move_to(cr, lx, Y_HDR_NAME)
    cairo_show_text(cr, date_p2)
    lx = lx + p2e.x_advance + DIV_PAD
    cairo_move_to(cr, lx, div_y) ; cairo_line_to(cr, lx, div_y + DIV_H) ; cairo_stroke(cr)
    lx = lx + DIV_PAD
    cairo_move_to(cr, lx, Y_HDR_NAME)
    cairo_show_text(cr, date_p3)

    -- Line 2: Month Year (centered)
    cairo_set_source_rgba(cr, green[1], green[2], green[3], green[4])
    cairo_select_font_face(cr, HDR_NAME_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, CTR_MAIN_PX)
    cairo_move_to(cr, main_x, Y_CTR_MAIN)
    cairo_show_text(cr, month_yr)

    -- Line 3: zodiac glyph + name
    if z then
        cairo_set_source_rgba(cr, COL_DAY[1], COL_DAY[2], COL_DAY[3], COL_DAY[4])
        cairo_select_font_face(cr, HDR_GLYPH_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, HDR_GLYPH_PX)
        cairo_move_to(cr, zglyph_x, Y_HDR_GLYPH)
        cairo_show_text(cr, z.sym)
        cairo_set_source_rgba(cr, purple[1], purple[2], purple[3], purple[4])
        cairo_select_font_face(cr, HDR_NAME_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, HDR_NAME_PX)
        cairo_move_to(cr, zname_x, Y_HDR_NAME)
        cairo_show_text(cr, z.name)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

--------------------------------------------------
-- TEXT OUTPUT: moon + sun times only
--------------------------------------------------
function conky_info_row()
    local sunrise, sunset = read_sun_times()
    local sun_line
    if sunrise and sunset then
        sun_line = "${font MonaspiceNe Nerd Font Mono:size=24}${voffset -14}${color FFB74D}󰖜${font MonaspiceNe Nerd Font Mono:size=10}${voffset -6}${color FFECB3} " .. sunrise ..
                   "${font DejaVuSansM Nerd Font Propo:size=10}        " .. moon_phase() .. "      " ..
                   "${font MonaspiceNe Nerd Font Mono:size=10}${color FFAB91}" .. sunset .. " ${font MonaspiceNe Nerd Font Mono:size=24}${voffset -12}${color FF7043}󰖛 ${font}"
    else
        sun_line = moon_phase()
    end
    return "${voffset 46}${goto 350}" .. sun_line
end

return M
