-- dial2.lua - Solar Dial with configurable dark/light theme
-- v2.0 2026-05-27 @rew62

require 'cairo'

local SCRIPT_DIR =
    debug.getinfo(1, "S").source:match("@?(.*/)") or "./"

----------------------------------------------------------
-- CONFIG
----------------------------------------------------------

local SIZE    = 300
local CENTER  = SIZE / 2
local ORBIT_R = 70

local OFFSET_X = 15
local OFFSET_Y = 15

----------------------------------------------------------
-- THEME
-- Set THEME = "dark" for dark wallpapers (default)
-- Set THEME = "light" for light/bright wallpapers
-- Set THEME = "ghost" for any wallpaper: day vanishes, night is dark navy
----------------------------------------------------------

local THEME = "light"

local function lerp(a, b, t) return a + (b - a) * t end

local THEMES = {
    dark = {
        -- bezel ring fill
        bezel_fill     = { 0.01, 0.02, 0.05, 0.96 },
        -- outer ring stroke
        ring_stroke    = { 0.70, 0.80, 1.00, 0.35 },
        -- tick mark rgb (alpha varies by tick weight)
        tick           = { 0.80, 0.90, 1.00 },
        tick_hi_a      = 0.50,   -- quarter-hour ticks
        tick_lo_a      = 0.20,   -- all other ticks
        -- hour numerals
        numeral        = { 0.80, 0.88, 1.00, 0.65 },
        -- inner sky boundary ring
        horizon        = { 1.00, 1.00, 1.00, 0.08 },
        -- orbit guide ring
        orbit_guide    = { 1.00, 1.00, 1.00, 0.08 },
        -- bright daytime arc (sunrise→sunset)
        daytime_arc    = { 1.00, 1.00, 1.00, 0.82 },
        -- second-ring ticks
        sec_active     = { 1.00, 1.00, 1.00, 0.95 },
        sec_inactive   = { 1.00, 1.00, 1.00, 0.10 },
        -- center glass gradient (top → bottom)
        glass_top      = { 1.00, 1.00, 1.00, 0.18 },
        glass_bot      = { 0.00, 0.00, 0.00, 0.18 },
        -- center time / date text
        time_text      = { 1.00, 1.00, 1.00, 0.96 },
        date_text      = { 1.00, 1.00, 1.00, 0.70 },
        -- sky color function (dark space palette)
        sky = function(alt)
            if    alt <  -18 then return 0.01, 0.01, 0.06, 0.85
            elseif alt < -12 then local t = (alt+18)/6
                return lerp(0.01,0.02,t), lerp(0.01,0.02,t), lerp(0.06,0.10,t), 0.85
            elseif alt <  -6 then local t = (alt+12)/6
                return lerp(0.02,0.06,t), lerp(0.02,0.03,t), lerp(0.10,0.12,t), 0.85
            elseif alt <   0 then local t = (alt+6)/6
                return lerp(0.06,0.22,t), lerp(0.03,0.10,t), lerp(0.12,0.05,t), 0.85
            elseif alt <   6 then local t = alt/6
                return lerp(0.22,0.40,t), lerp(0.10,0.22,t), lerp(0.05,0.05,t), 0.85
            elseif alt <  20 then local t = (alt-6)/14
                return lerp(0.40,0.14,t), lerp(0.22,0.26,t), lerp(0.05,0.40,t), 0.85
            else  return 0.04, 0.14, 0.38, 0.85
            end
        end,
        frosted_base  = false,
        annular_bezel = false,
        vignette      = { 0.45, 0.20, 0.00 },
        atm_alphas    = { 0.72, 0.25, 0.00, 0.00, 0.30, 0.60 },
    },
    light = {
        -- pale green bezel
        bezel_fill     = { 1.00, 1.00, 1.00, 0.20 },
        -- ring stroke
        ring_stroke    = { 1.00, 1.00, 1.00, 0.55 },
        -- ticks
        tick           = { 1.00, 1.00, 1.00 },
        tick_hi_a      = 0.60,
        tick_lo_a      = 0.28,
        -- numerals
        numeral        = { 1.00, 1.00, 1.00, 0.85 },
        -- horizon/orbit lines
        horizon        = { 1.00, 1.00, 1.00, 0.18 },
        orbit_guide    = { 0.00, 0.00, 0.00, 0.18 },
        -- daytime arc
        daytime_arc    = { 1.00, 1.00, 1.00, 0.82 },
        -- second-ring ticks
        sec_active     = { 1.00, 1.00, 1.00, 0.90 },
        sec_inactive   = { 1.00, 1.00, 1.00, 0.15 },
        -- center glass
        glass_top      = { 1.00, 1.00, 1.00, 0.55 },
        glass_bot      = { 0.65, 0.70, 0.80, 0.30 },
        -- center text
        time_text      = { 1.00, 1.00, 1.00, 0.95 },
        date_text      = { 1.00, 1.00, 1.00, 0.80 },
        -- sky color function (light pastel palette)
        sky = function(alt)
            if    alt <  -18 then return 0.35, 0.38, 0.62, 0.80
            elseif alt < -12 then local t = (alt+18)/6
                return lerp(0.35,0.48,t), lerp(0.38,0.44,t), lerp(0.62,0.66,t), lerp(0.80,0.75,t)
            elseif alt <  -6 then local t = (alt+12)/6
                return lerp(0.48,0.65,t), lerp(0.44,0.48,t), lerp(0.66,0.60,t), lerp(0.75,0.70,t)
            elseif alt <   0 then local t = (alt+6)/6
                return lerp(0.65,0.88,t), lerp(0.48,0.62,t), lerp(0.60,0.48,t), lerp(0.70,0.62,t)
            elseif alt <   6 then local t = alt/6
                return lerp(0.88,0.72,t), lerp(0.62,0.78,t), lerp(0.48,0.56,t), lerp(0.62,0.58,t)
            else  return 0.52, 0.74, 0.92, 0.30
            end
        end,
        frosted_base  = false,
        annular_bezel = false,
        vignette      = { 0.35, 0.08, 0.00 },
        atm_alphas    = { 0.00, 0.00, 0.00, 0.00, 0.00, 0.00 },
    },
    ghost = {
        bezel_fill     = { 0.04, 0.06, 0.12, 0.20 },
        ring_stroke    = { 0.70, 0.80, 1.00, 0.35 },
        tick           = { 0.80, 0.90, 1.00 },
        tick_hi_a      = 0.50,
        tick_lo_a      = 0.20,
        numeral        = { 0.80, 0.88, 1.00, 0.65 },
        horizon        = { 1.00, 1.00, 1.00, 0.08 },
        orbit_guide    = { 1.00, 1.00, 1.00, 0.08 },
        daytime_arc    = { 1.00, 1.00, 1.00, 0.82 },
        sec_active     = { 1.00, 1.00, 1.00, 0.95 },
        sec_inactive   = { 1.00, 1.00, 1.00, 0.10 },
        glass_top      = { 1.00, 1.00, 1.00, 0.18 },
        glass_bot      = { 0.00, 0.00, 0.00, 0.18 },
        time_text      = { 1.00, 1.00, 1.00, 0.96 },
        date_text      = { 1.00, 1.00, 1.00, 0.70 },
        -- sky color function (ghost: dark navy night → sky blue day, alpha-ramp)
        sky = function(alt)
            if    alt <  -18 then return 0.04, 0.06, 0.18, 0.78
            elseif alt < -12 then local t = (alt+18)/6
                return lerp(0.04,0.08,t), lerp(0.06,0.12,t), lerp(0.18,0.28,t), lerp(0.78,0.75,t)
            elseif alt <  -6 then local t = (alt+12)/6
                return lerp(0.08,0.14,t), lerp(0.12,0.20,t), lerp(0.28,0.44,t), lerp(0.75,0.68,t)
            elseif alt <   0 then local t = (alt+6)/6
                return lerp(0.14,0.28,t), lerp(0.20,0.42,t), lerp(0.44,0.72,t), lerp(0.68,0.48,t)
            elseif alt <   6 then local t = alt/6
                return lerp(0.28,0.52,t), lerp(0.42,0.70,t), lerp(0.72,0.96,t), lerp(0.48,0.10,t)
            else  return 0.52, 0.70, 0.96, 0.08
            end
        end,
        frosted_base  = false,
        annular_bezel = false,
        vignette      = { 0.40, 0.15, 0.00 },
        atm_alphas    = { 0.00, 0.00, 0.00, 0.00, 0.00, 0.00 },
    },
}

local T = THEMES[THEME]

----------------------------------------------------------
-- LOAD ENV
----------------------------------------------------------

local function load_env()

    local f = io.open(SCRIPT_DIR .. "../.env","r")

    if not f then
        return
    end

    for line in f:lines() do

        local k,v =
            line:match("^([%w_]+)%=(.+)$")

        if k == "LAT" then
            LAT = tonumber(v)
        end

        if k == "LON" then
            LON = tonumber(v)
        end
    end

    f:close()
end

load_env()

----------------------------------------------------------
-- COMPLICATIONS CONFIG
----------------------------------------------------------

local COMPLICATION_SLOTS = {
    top_left     = "ram",
    top_right    = "cpu_load",
    bottom_left  = "fs",
    bottom_right = "cpu_temp",
}

local CORNER_POS = {
    top_left     = { cx = 150, cy = 150, r = 150 },
    top_right    = { cx = 150, cy = 150, r = 150 },
    bottom_left  = { cx = 150, cy = 150, r = 150 },
    bottom_right = { cx = 150, cy = 150, r = 150 },
}

local complication_cache = {}

local function load_complication(name)
    if complication_cache[name] == nil then
        local path = SCRIPT_DIR .. "complications/" .. name .. ".lua"
        local ok, result = pcall(dofile, path)
        if ok and type(result) == "table"
                and type(result.draw) == "function" then
            complication_cache[name] = result
        else
            complication_cache[name] = false
        end
    end
    return complication_cache[name]
end

----------------------------------------------------------
-- CACHE SURFACES
----------------------------------------------------------

local static_surface = nil
local solar_surface  = nil

local last_minute = -1

----------------------------------------------------------
-- HELPERS
----------------------------------------------------------

local function rgba(cr, r, g, b, a)
    cairo_set_source_rgba(cr, r, g, b, a)
end

-- Unpack a theme color table into rgba()
local function trgba(cr, c)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
end

local function rad(v)
    return v * math.pi / 180
end

local function polar(cx, cy, r, a)
    return
        cx + math.cos(a - math.pi/2) * r,
        cy + math.sin(a - math.pi/2) * r
end

local function h2a(h)
    return (h - 12) / 24 * 2 * math.pi - math.pi / 2
end

----------------------------------------------------------
-- TIMEZONE / PRECISE SOLAR MATH
----------------------------------------------------------

local function tz_offset()
    local z = os.date("%z") or "+0000"
    local sign = z:sub(1,1) == "-" and -1 or 1
    return sign * ((tonumber(z:sub(2,3)) or 0) + (tonumber(z:sub(4,5)) or 0) / 60)
end

local function jd(y, mo, d, utc)
    if mo <= 2 then y = y - 1; mo = mo + 12 end
    local A = math.floor(y / 100); local B = 2 - A + math.floor(A / 4)
    return math.floor(365.25 * (y + 4716)) + math.floor(30.6001 * (mo + 1)) + d + B - 1524.5 + utc / 24
end

local function sun_alt_at(y, mo, d, lh, tz)
    local utc = lh - tz; local dd, mm, yy = d, mo, y
    if utc >= 24 then utc = utc - 24; dd = dd + 1
    elseif utc < 0 then utc = utc + 24; dd = dd - 1 end
    local n   = jd(yy, mm, dd, utc) - 2451545
    local L   = math.fmod(280.46 + 0.9856474 * n, 360)
    local g   = rad(math.fmod(357.528 + 0.9856003 * n, 360))
    local lam = rad(L + 1.915 * math.sin(g) + 0.020 * math.sin(2 * g))
    local eps = rad(23.439 - 4e-7 * n)
    local sin_dec = math.sin(eps) * math.sin(lam)
    local dec = math.asin(sin_dec)
    local RA  = math.atan2(math.cos(eps) * math.sin(lam), math.cos(lam))
    local n0  = jd(yy, mm, dd, 0) - 2451545
    local GMST = math.fmod(6.697375 + 0.0657098242 * n0 + utc * 1.00273791, 24)
    if GMST < 0 then GMST = GMST + 24 end
    local LMST = math.fmod(GMST + LON / 15, 24); if LMST < 0 then LMST = LMST + 24 end
    local HA   = rad(LMST * 15) - RA
    local latR = rad(LAT)
    return math.deg(math.asin(math.sin(latR) * sin_dec + math.cos(latR) * math.cos(dec) * math.cos(HA)))
end

local function alt_to_sector_color(alt)
    return T.sky(alt)
end

local function draw_sky(cr, y, mo, d, tz)
    local r    = 124
    local SEGS = 240
    cairo_save(cr)
    cairo_arc(cr, CENTER, CENTER, r, 0, 2 * math.pi)
    cairo_clip(cr)

    if T.frosted_base then
        local fg = cairo_pattern_create_radial(CENTER, CENTER, r*0.40, CENTER, CENTER, r)
        cairo_pattern_add_color_stop_rgba(fg, 0.0, 0.95, 0.97, 1.0, 0.90)
        cairo_pattern_add_color_stop_rgba(fg, 0.7, 0.95, 0.97, 1.0, 0.82)
        cairo_pattern_add_color_stop_rgba(fg, 1.0, 0.95, 0.97, 1.0, 0.00)
        cairo_arc(cr, CENTER, CENTER, r, 0, 2 * math.pi)
        cairo_set_source(cr, fg); cairo_fill(cr); cairo_pattern_destroy(fg)
    end

    local overlap = (2 * math.pi / SEGS) * 0.5
    for i = 0, SEGS - 1 do
        local h_mid = (i + 0.5) / SEGS * 24
        local a1    = h2a(i       / SEGS * 24)
        local a2    = h2a((i + 1) / SEGS * 24) + overlap
        local alt   = sun_alt_at(y, mo, d, h_mid, tz)
        local sr, sg, sb, sa = alt_to_sector_color(alt)
        cairo_move_to(cr, CENTER, CENTER)
        cairo_arc(cr, CENTER, CENTER, r, a1, a2)
        cairo_close_path(cr)
        cairo_set_source_rgba(cr, sr, sg, sb, sa)
        cairo_fill(cr)
    end

    local aa = T.atm_alphas
    local atm = cairo_pattern_create_linear(CENTER, CENTER - r, CENTER, CENTER + r)
    cairo_pattern_add_color_stop_rgba(atm, 0.00, 0.00, 0.00, 0.18, aa[1])
    cairo_pattern_add_color_stop_rgba(atm, 0.28, 0.00, 0.00, 0.10, aa[2])
    cairo_pattern_add_color_stop_rgba(atm, 0.45, 0.00, 0.00, 0.00, aa[3])
    cairo_pattern_add_color_stop_rgba(atm, 0.55, 0.00, 0.00, 0.00, aa[4])
    cairo_pattern_add_color_stop_rgba(atm, 0.72, 0.00, 0.00, 0.00, aa[5])
    cairo_pattern_add_color_stop_rgba(atm, 1.00, 0.00, 0.00, 0.00, aa[6])
    cairo_set_source(cr, atm); cairo_paint(cr); cairo_pattern_destroy(atm)

    local vi = T.vignette
    local vg = cairo_pattern_create_radial(CENTER, CENTER, r * vi[1], CENTER, CENTER, r)
    cairo_pattern_add_color_stop_rgba(vg, 0.0, 0, 0, 0, 0)
    cairo_pattern_add_color_stop_rgba(vg, 0.6, 0, 0, 0, vi[2])
    cairo_pattern_add_color_stop_rgba(vg, 1.0, 0, 0, 0, vi[3])
    cairo_set_source(cr, vg); cairo_paint(cr); cairo_pattern_destroy(vg)

    cairo_restore(cr)
end

----------------------------------------------------------
-- SOLAR MATH
----------------------------------------------------------

local function day_of_year()
    return tonumber(os.date("%j"))
end

local function solar_declination(n)
    return 23.44 * math.sin(rad((360 / 365) * (n - 81)))
end

local function daylight_hours(lat, decl)
    local latRad = rad(lat)
    local decRad = rad(decl)
    local h = math.acos(-math.tan(latRad) * math.tan(decRad))
    return (2 * h * 24) / (2 * math.pi)
end

local function sunrise_sunset()
    local n        = day_of_year()
    local decl     = solar_declination(n)
    local daylight = daylight_hours(LAT, decl)
    local sunrise  = 12 - daylight / 2
    local sunset   = 12 + daylight / 2
    return sunrise, sunset
end

local _ev_cache = { day = -1, month = -1 }

local function solar_events_accurate(y, mo, d, tz)
    if _ev_cache.day == d and _ev_cache.month == mo then
        return _ev_cache
    end
    local best_alt, noon = -999, 12
    for i = 0, 200 do
        local h = 6 + i * 0.06
        local a = sun_alt_at(y, mo, d, h, tz)
        if a > best_alt then best_alt = a; noon = h end
    end
    local sr = nil
    if sun_alt_at(y, mo, d, 0.01, tz) < -0.833 and best_alt > -0.833 then
        local h0, h1 = 0, noon
        for _ = 1, 52 do
            local m = (h0 + h1) / 2
            if sun_alt_at(y, mo, d, m, tz) < -0.833 then h0 = m else h1 = m end
            if h1 - h0 < 3e-4 then break end
        end
        sr = (h0 + h1) / 2
    end
    local ss = nil
    if best_alt > -0.833 and sun_alt_at(y, mo, d, 23.99, tz) < -0.833 then
        local h0, h1 = noon, 24
        for _ = 1, 52 do
            local m = (h0 + h1) / 2
            if sun_alt_at(y, mo, d, m, tz) > -0.833 then h0 = m else h1 = m end
            if h1 - h0 < 3e-4 then break end
        end
        ss = (h0 + h1) / 2
    end
    _ev_cache = { day = d, month = mo, sunrise = sr, sunset = ss, noon = noon }
    return _ev_cache
end

----------------------------------------------------------
-- BUILD STATIC LAYER
----------------------------------------------------------

local function build_static()

    static_surface =
        cairo_image_surface_create(CAIRO_FORMAT_ARGB32, SIZE, SIZE)

    local cr = cairo_create(static_surface)

    -- Bezel ring (even-odd leaves inner sky transparent)
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
    cairo_arc(cr, CENTER, CENTER, 134, 0, 2 * math.pi)
    cairo_new_sub_path(cr)
    cairo_arc_negative(cr, CENTER, CENTER, 124, 2 * math.pi, 0)
    trgba(cr, T.bezel_fill)
    cairo_fill(cr)
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING)

    -- Outer ring
    cairo_arc(cr, CENTER, CENTER, 128, 0, 2 * math.pi)
    cairo_set_line_width(cr, 1.5)
    trgba(cr, T.ring_stroke)
    cairo_stroke(cr)

    -- Ticks
    for i = 0, 143 do
        local a          = (i / 144) * 2 * math.pi
        local is_quarter = (i % 36 == 0)
        local r1         = 116
        local r2         = is_quarter and 130 or (i % 6 == 0) and 128 or 123
        local x1, y1     = polar(CENTER, CENTER, r1, a)
        local x2, y2     = polar(CENTER, CENTER, r2, a)
        cairo_move_to(cr, x1, y1)
        cairo_line_to(cr, x2, y2)
        cairo_set_line_width(cr, (i % 6 == 0) and 1.5 or 1)
        cairo_set_source_rgba(cr,
            T.tick[1], T.tick[2], T.tick[3],
            is_quarter and T.tick_hi_a or T.tick_lo_a)
        cairo_stroke(cr)
    end

    -- Hour numerals
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 18)

    for h = 0, 22, 2 do
        local a     = ((h - 12) / 24) * 2 * math.pi
        local x, y  = polar(CENTER, CENTER, 100, a)
        local label = (h == 0) and "24" or string.format("%02d", h)
        local ext   = cairo_text_extents_t:create()
        cairo_text_extents(cr, label, ext)
        trgba(cr, T.numeral)
        cairo_move_to(cr, x - ext.width / 2, y + ext.height / 2)
        cairo_show_text(cr, label)
    end

    cairo_destroy(cr)
end

----------------------------------------------------------
-- BUILD SOLAR LAYER
----------------------------------------------------------

local function build_solar()

    solar_surface =
        cairo_image_surface_create(CAIRO_FORMAT_ARGB32, SIZE, SIZE)

    local cr     = cairo_create(solar_surface)
    local now_t  = os.date("*t")
    local tz     = tz_offset()
    local ev     = solar_events_accurate(now_t.year, now_t.month, now_t.day, tz)
    local sunrise, sunset = ev.sunrise, ev.sunset

    draw_sky(cr, now_t.year, now_t.month, now_t.day, tz)

    if T.annular_bezel then
        local bz = cairo_pattern_create_radial(CENTER, CENTER, 104, CENTER, CENTER, 124)
        cairo_pattern_add_color_stop_rgba(bz, 0.0, 0.10, 0.10, 0.10, 0.0)
        cairo_pattern_add_color_stop_rgba(bz, 0.3, 0.10, 0.10, 0.10, 0.7)
        cairo_pattern_add_color_stop_rgba(bz, 1.0, 0.06, 0.06, 0.06, 0.92)
        cairo_arc(cr, CENTER, CENTER, 124, 0, 2 * math.pi)
        cairo_set_source(cr, bz); cairo_fill(cr); cairo_pattern_destroy(bz)
    end

    local sunriseA = sunrise and ((sunrise - 12) / 24) * 2 * math.pi
    local sunsetA  = sunset  and ((sunset  - 12) / 24) * 2 * math.pi

    -- Sunrise glow
    if sunriseA then
        cairo_arc(cr, CENTER, CENTER, 126,
            sunriseA - 0.08 - math.pi / 2,
            sunriseA + 0.08 - math.pi / 2)
        cairo_set_line_width(cr, 8)
        rgba(cr, 1.0, 0.72, 0.35, 0.25)
        cairo_stroke(cr)
    end

    -- Sunset glow
    if sunsetA then
        cairo_arc(cr, CENTER, CENTER, 126,
            sunsetA - 0.08 - math.pi / 2,
            sunsetA + 0.08 - math.pi / 2)
        cairo_set_line_width(cr, 8)
        rgba(cr, 1.0, 0.55, 0.30, 0.25)
        cairo_stroke(cr)
    end

    -- Horizon ring
    cairo_arc(cr, CENTER, CENTER, 124, 0, 2 * math.pi)
    cairo_set_line_width(cr, 1.5)
    trgba(cr, T.horizon)
    cairo_stroke(cr)

    -- Orbit guide ring
    cairo_new_path(cr)
    cairo_arc(cr, CENTER, CENTER, ORBIT_R, 0, 2 * math.pi)
    cairo_set_line_width(cr, 1.0)
    trgba(cr, T.orbit_guide)
    cairo_stroke(cr)

    -- Bright daytime arc (sunrise → sunset through noon)
    if sunrise and sunset then
        cairo_new_path(cr)
        cairo_arc(cr, CENTER, CENTER, ORBIT_R,
            sunriseA - math.pi / 2, sunsetA - math.pi / 2)
        cairo_set_line_width(cr, 2.0)
        trgba(cr, T.daytime_arc)
        cairo_stroke(cr)
    end

    -- Solar noon dot (always golden — it's the sun)
    local noonA = h2a(ev.noon or 12)
    local nx = CENTER + math.cos(noonA) * ORBIT_R
    local ny = CENTER + math.sin(noonA) * ORBIT_R
    cairo_new_path(cr)
    cairo_arc(cr, nx, ny, 2.5, 0, 2 * math.pi)
    rgba(cr, 1, 1, 0.5, 0.75)
    cairo_fill(cr)

    cairo_destroy(cr)
end

----------------------------------------------------------
-- DYNAMIC LAYER
----------------------------------------------------------

local function draw_dynamic(cr)

    local now     = os.date("*t")
    local seconds = now.sec + (os.clock() % 1)
    local minutes = now.min + seconds / 60
    local hours   = now.hour + minutes / 60

    -- Second ring
    for i = 1, 60 do
        local a      = (i / 60) * 2 * math.pi
        local x1, y1 = polar(CENTER, CENTER, 47, a)
        local x2, y2 = polar(CENTER, CENTER, 54, a)
        cairo_move_to(cr, x1, y1)
        cairo_line_to(cr, x2, y2)
        cairo_set_line_width(cr, 1.5)
        if i <= seconds then
            trgba(cr, T.sec_active)
        else
            trgba(cr, T.sec_inactive)
        end
        cairo_stroke(cr)
    end

    -- Sun dot on orbit ring
    local tz      = tz_offset()
    local cur_alt = sun_alt_at(now.year, now.month, now.day, hours, tz)
    local handA   = ((hours - 12) / 24) * 2 * math.pi
    local hx, hy  = polar(CENTER, CENTER, ORBIT_R, handA)

    local dr, dg, db
    if cur_alt > 0 then
        dr, dg, db = 1.00, 0.92, 0.35
    elseif cur_alt > -8 then
        local t = (cur_alt + 8) / 8
        dr = lerp(0.40, 1.00, t)
        dg = lerp(0.50, 0.92, t)
        db = lerp(0.75, 0.35, t)
    else
        dr, dg, db = 0.40, 0.50, 0.75
    end

    cairo_new_path(cr)
    for i = 16, 1, -1 do
        cairo_arc(cr, hx, hy, i, 0, 2 * math.pi)
        cairo_set_source_rgba(cr, dr, dg, db, 0.030 * (17 - i) / 16)
        cairo_fill(cr)
    end
    cairo_arc(cr, hx, hy, 9, 0, 2 * math.pi)
    rgba(cr, dr, dg, db, 1.0)
    cairo_fill(cr)
    cairo_arc(cr, hx, hy, 9, 0, 2 * math.pi)
    rgba(cr, 0, 0, 0, 0.40)
    cairo_set_line_width(cr, 2.2)
    cairo_stroke(cr)
    cairo_arc(cr, hx - 3, hy - 3, 3, 0, 2 * math.pi)
    rgba(cr, 1, 1, 1, 0.50)
    cairo_fill(cr)

    -- Center glass
    cairo_arc(cr, CENTER, CENTER, 39, 0, 2 * math.pi)
    local glassPat = cairo_pattern_create_linear(0, CENTER - 45, 0, CENTER + 45)
    cairo_pattern_add_color_stop_rgba(glassPat, 0,
        T.glass_top[1], T.glass_top[2], T.glass_top[3], T.glass_top[4])
    cairo_pattern_add_color_stop_rgba(glassPat, 1,
        T.glass_bot[1], T.glass_bot[2], T.glass_bot[3], T.glass_bot[4])
    cairo_set_source(cr, glassPat)
    cairo_fill(cr)
    cairo_pattern_destroy(glassPat)

    -- Center time
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 28)

    local timeStr = string.format("%d:%02d",
        ((now.hour - 1) % 12) + 1, now.min)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, timeStr, ext)
    trgba(cr, T.time_text)
    cairo_move_to(cr, CENTER - ext.width / 2, CENTER + ext.height / 2 - 8)
    cairo_show_text(cr, timeStr)

    -- Center date
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)

    local dateStr = os.date("%a %b %d")
    local dext    = cairo_text_extents_t:create()
    cairo_text_extents(cr, dateStr, dext)
    trgba(cr, T.date_text)
    cairo_move_to(cr,
        CENTER - dext.width / 2,
        CENTER + ext.height / 2 + 10)
    cairo_show_text(cr, dateStr)

    -- Sun phase label (twilight phases only)
    local sun_phase = nil
    if     cur_alt >  0 and cur_alt <=  6 then sun_phase = "Golden hour"
    elseif cur_alt > -6 and cur_alt <=  0 then sun_phase = "Civil twilight"
    elseif cur_alt > -12 and cur_alt <= -6 then sun_phase = "Nautical twilight"
    elseif cur_alt > -18 and cur_alt <= -12 then sun_phase = "Astronomical twilight"
    end

    if sun_phase then
        cairo_select_font_face(cr, "DejaVu Sans",
            CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 10)
        local se = cairo_text_extents_t:create()
        cairo_text_extents(cr, sun_phase, se)
        local sr, sg, sb = alt_to_sector_color(cur_alt)
        rgba(cr,
            math.min(1, sr + 0.15),
            math.min(1, sg + 0.15),
            math.min(1, sb + 0.25),
            0.90)
        cairo_move_to(cr,
            CENTER - (se.width / 2 + se.x_bearing),
            CENTER + ext.height / 2 + 24)
        cairo_show_text(cr, sun_phase)
    end

    -- Complications
    for slot, name in pairs(COMPLICATION_SLOTS) do
        if name then
            local mod = load_complication(name)
            if mod then
                local pos = CORNER_POS[slot]
                mod.draw(cr, pos.cx, pos.cy, pos.r)
            end
        end
    end
end

----------------------------------------------------------
-- MAIN
----------------------------------------------------------

function conky_solar_dial()

    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)

    local cr = cairo_create(cs)

    if not static_surface then
        build_static()
    end

    local minute = tonumber(os.date("%M"))
    if minute ~= last_minute then
        build_solar()
        last_minute = minute
    end

    cairo_set_source_surface(cr, solar_surface,  OFFSET_X, OFFSET_Y)
    cairo_paint(cr)
    cairo_set_source_surface(cr, static_surface, OFFSET_X, OFFSET_Y)
    cairo_paint(cr)
    cairo_translate(cr, OFFSET_X, OFFSET_Y)
    draw_dynamic(cr)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
