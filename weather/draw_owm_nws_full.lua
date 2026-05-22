-- draw_owm_nws_full.lua - full Lua/Cairo script combining NWS forecast and OWM current conditions
-- NWS data via get_forecast() / get_grid_info() from scripts/nws_fetch.lua
-- OWM data via owm_get() from scripts/owm_fetch.lua
-- v1.2 2026-05-21 @rew62

require 'cairo'

package.path = package.path .. ";./?.lua;../?.lua;" .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

-- -----------------------------------------------------------------------
-- CONFIGURATION
-- -----------------------------------------------------------------------
local DAYS_TO_SHOW = 5
local WIN_W, PAD   = 300, 12
local FONT_NAME    = cairo_font or "DejaVuSansM Nerd Font Propo"

-- Colors (RGBA)
local COL_TEXT   = { 0.85, 0.85, 0.85, 1.0 }
local COL_DIM    = { 0.55, 0.55, 0.55, 1.0 }
local COL_HIGH   = { 1.00, 0.65, 0.20, 1.0 }
local COL_LOW    = { 0.35, 0.75, 1.00, 1.0 }
local COL_ACCENT = { 0.40, 0.90, 0.40, 1.0 }
local COL_SEP    = { 0.30, 0.30, 0.30, 0.7 }

-- -----------------------------------------------------------------------
-- ICON HELPERS  (MET Norway via jsDelivr CDN)
-- -----------------------------------------------------------------------
local ICON_DIR   = "/dev/shm/conky_icons/"
local METNO_BASE = "https://cdn.jsdelivr.net/gh/metno/weathericons@main/weather/png/"

local _mtime_cache   = nil
local _mtime_checked = 0

do
    os.execute("mkdir -p " .. ICON_DIR)
    local h = io.popen("stat -c %Y /dev/shm/nws_forecast.json 2>/dev/null")
    if h then
        _mtime_cache   = tonumber(h:read("*l"))
        _mtime_checked = os.time()
        h:close()
    end
end

local NWS_TO_METNO = {
    clear                  = "clearsky_day",
    clear_day              = "clearsky_day",
    clear_night            = "clearsky_night",
    few_clouds             = "fair_day",
    few_clouds_day         = "fair_day",
    few_clouds_night       = "fair_night",
    scattered_clouds       = "partlycloudy_day",
    scattered_clouds_day   = "partlycloudy_day",
    scattered_clouds_night = "partlycloudy_night",
    broken_clouds          = "cloudy",
    broken_clouds_day      = "cloudy",
    broken_clouds_night    = "cloudy",
    overcast               = "cloudy",
    overcast_day           = "cloudy",
    overcast_night         = "cloudy",
    rain                   = "rain",
    showers                = "rainshowers_day",
    showers_day            = "rainshowers_day",
    showers_night          = "rainshowers_night",
    snow                   = "snow",
    sleet                  = "sleet",
    freezing_rain          = "sleet",
    blizzard               = "heavysnow",
    thunderstorm           = "rainandthunder",
    thunderstorm_day       = "rainandthunder",
    thunderstorm_night     = "rainandthunder",
    windy                  = "partlycloudy_day",
    windy_clouds           = "partlycloudy_day",
    windy_overcast         = "cloudy",
    fog                    = "fog",
    haze                   = "fog",
    haze_day               = "fog",
    haze_night             = "fog",
    smoke                  = "fog",
    dust                   = "fog",
    tornado                = "rainandthunder",
    hurricane              = "rainandthunder",
    tropical_storm         = "rainandthunder",
    hot                    = "clearsky_day",
    cold                   = "clearsky_day",
}

local function fetch_metno_icon(name)
    local path = ICON_DIR .. "metno_" .. name .. ".png"
    local f = io.open(path, "r")
    if f then f:close(); return path end
    os.execute(string.format('curl -sfL "%s" -o "%s" &', METNO_BASE .. name .. ".png", path))
    local fallback = ICON_DIR .. "metno_clearsky_day.png"
    local fb = io.open(fallback, "r")
    if fb then fb:close(); return fallback end
    return path
end

local function nws_icon_path(icon_token)
    if not icon_token or icon_token == "" then return fetch_metno_icon("clearsky_day") end
    local name = NWS_TO_METNO[icon_token]
               or NWS_TO_METNO[icon_token:gsub("_day$",""):gsub("_night$","")]
               or "partlycloudy_day"
    return fetch_metno_icon(name)
end

-- -----------------------------------------------------------------------
-- DRAWING HELPERS
-- -----------------------------------------------------------------------
local _text_ext = nil
local function get_ext(cr)
    if not _text_ext then _text_ext = cairo_text_extents_t:create() end
    return _text_ext
end

local function draw_text(cr, text, x, y, size, col, align, bold)
    cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4])
    cairo_select_font_face(cr, FONT_NAME,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    if align == "center" or align == "right" then
        local ext = get_ext(cr)
        cairo_text_extents(cr, tostring(text), ext)
        if     align == "center" then x = x - (ext.width / 2 + ext.x_bearing)
        elseif align == "right"  then x = x - ext.width - ext.x_bearing
        end
    end
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(text))
end

local function draw_image(cr, path, x, y, w, h)
    local surf = cairo_image_surface_create_from_png(path)
    if cairo_surface_status(surf) ~= 0 then cairo_surface_destroy(surf); return end
    local iw = cairo_image_surface_get_width(surf)
    local ih = cairo_image_surface_get_height(surf)
    if iw == 0 or ih == 0 then cairo_surface_destroy(surf); return end
    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_scale(cr, w / iw, h / ih)
    cairo_set_source_surface(cr, surf, 0, 0)
    cairo_paint(cr)
    cairo_restore(cr)
    cairo_surface_destroy(surf)
end

-- -----------------------------------------------------------------------
-- DATE HELPERS
-- -----------------------------------------------------------------------
local MONTHS = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
local DAYS   = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}

local function parse_date_strings(iso)
    if not iso or iso == "" then return "---", "" end
    local y, m, d = iso:match("(%d%d%d%d)-(%d%d)-(%d%d)")
    if not y then return "---", "" end
    local t = os.time({ year=tonumber(y), month=tonumber(m), day=tonumber(d) })
    local dow = DAYS[tonumber(os.date("%w", t)) + 1]
    return dow, MONTHS[tonumber(m)] .. " " .. tostring(tonumber(d))
end

local function cache_update_time()
    local now = os.time()
    if _mtime_cache and (now - _mtime_checked) < 300 then
        return os.date("%I:%M %p", _mtime_cache):gsub("^0", "")
    end
    local h = io.popen("stat -c %Y /dev/shm/nws_forecast.json 2>/dev/null")
    if not h then return _mtime_cache and os.date("%I:%M %p", _mtime_cache):gsub("^0", "") or "" end
    local t = tonumber(h:read("*l"))
    h:close()
    if t then _mtime_cache = t; _mtime_checked = now end
    return _mtime_cache and os.date("%I:%M %p", _mtime_cache):gsub("^0", "") or ""
end

-- -----------------------------------------------------------------------
-- MAIN DRAW
-- -----------------------------------------------------------------------
local function do_draw(cr)
    if conky_owm_fetch then conky_owm_fetch() end

    local fc   = get_forecast() or {}
    local grid = get_grid_info() or { city = "Local", state = "Weather" }

    local temp      = owm_get("temp")
    local feels     = owm_get("feels_like")
    local desc      = owm_get("desc", "")
    local wind      = owm_get("wind_speed")
    local wind_unit = owm_get("wind_unit", "mph")
    local temp_unit = owm_get("temp_unit", "°F")
    local icon_metno = owm_get("icon_metno", "partlycloudy_day")
    local has_current = (temp ~= "N/A" and temp ~= "--")

    local y = 20

    -- Header: location left, cache update time right
    local loc = (grid.city or "Local") .. ", " .. (grid.state or "")
    draw_text(cr, loc,                PAD,       y, 11, COL_ACCENT, "left",  true)
    draw_text(cr, cache_update_time(), WIN_W-PAD, y,  9, COL_DIM,   "right", false)
    y = y + 20

    -- Current conditions
    if has_current then
        draw_text(cr, temp .. temp_unit,               PAD, y + 30, 36, COL_TEXT, "left",  true)
        draw_text(cr, desc,                            PAD, y + 46, 10, COL_DIM,  "left",  false)
        draw_text(cr, "Feels like " .. feels .. "°",  PAD, y + 58,  9, COL_DIM,  "left",  false)
        draw_text(cr, "Wind: " .. wind .. " " .. wind_unit, PAD, y + 70, 9, COL_DIM, "left", false)
        draw_image(cr, fetch_metno_icon(icon_metno), WIN_W - 100, y - 15, 70, 70)
        y = y + 85
    end

    -- Separator
    cairo_set_source_rgba(cr, COL_SEP[1], COL_SEP[2], COL_SEP[3], COL_SEP[4])
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, PAD, y)
    cairo_line_to(cr, WIN_W - PAD, y)
    cairo_stroke(cr)
    y = y + 10

    -- 5-day forecast
    if #fc > 0 then
        local col_w = (WIN_W - PAD * 2) / DAYS_TO_SHOW
        for i = 1, math.min(DAYS_TO_SHOW, #fc) do
            local d  = fc[i]
            local cx = PAD + (i - 1) * col_w + col_w / 2 + 2

            local dow, date_str = parse_date_strings(d.date)
            draw_text(cr, dow,      cx, y,      10, COL_TEXT, "center", true)
            draw_text(cr, date_str, cx, y + 14,  8, COL_DIM,  "center", false)

            draw_image(cr, nws_icon_path(d.icon), cx - 18, y + 18, 40, 40)

            local short = (d.short_fcst or ""):match("^(.-) then") or d.short_fcst or ""
            if #short > 12 then short = short:sub(1, 10) .. ".." end
            draw_text(cr, short, cx, y + 65, 7, COL_DIM, "center", false)

            local h_val = tonumber(d.temp_high)
            local l_val = tonumber(d.temp_low)
            local pop   = tonumber(d.pop) or 0

            draw_text(cr, (h_val and h_val .. "°" or "-"), cx, y + 76,  11, COL_HIGH,   "center", true)
            draw_text(cr, (l_val and l_val .. "°" or "-"), cx, y + 90,  10, COL_LOW,    "center", false)
            draw_text(cr, (pop > 0 and pop .. "%" or "-"), cx, y + 104,  8, COL_ACCENT, "center", false)
        end
    end
end

-- -----------------------------------------------------------------------
-- CONKY ENTRY POINT
-- -----------------------------------------------------------------------
function conky_weather_main()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual,  conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    local ok, err = pcall(do_draw, cr)
    if not ok then print("alien-weather-full draw error: " .. tostring(err)) end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
