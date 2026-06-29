-- draw_nws_forecast_sidepanel.lua - 5-day NWS forecast widget (no current conditions)
-- Renderer only; data from nws_fetch.lua (loaded first via lua_load)
-- Modelled on weather/alien-weather-full.lua; current-conditions block removed.
-- v1.1 2026-05-19 @rew62

require 'cairo'

package.path = package.path .. ";./?.lua;../?.lua;" .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

-- -----------------------------------------------------------------------
-- CONFIGURATION
-- -----------------------------------------------------------------------
local DAYS_TO_SHOW = 5
local X_OFFSET     = 3      -- shift content right within the window
local Y_OFFSET     = 7      -- shift content down within the window

-- -----------------------------------------------------------------------
-- INTERNAL SETTINGS
-- -----------------------------------------------------------------------
local ICON_DIR  = "/dev/shm/conky/icons/"
local WIN_W     = 318       -- window width (325) minus X_OFFSET
local PAD       = 12
local FONT_NAME = cairo_font or "DejaVuSansM Nerd Font Propo"

-- Colors (RGBA)
local COL_TEXT   = { 0.85, 0.85, 0.85, 1.0 }
local COL_DIM    = { 0.55, 0.55, 0.55, 1.0 }
local COL_HIGH   = { 1.00, 0.65, 0.20, 1.0 }
local COL_LOW    = { 0.35, 0.75, 1.00, 1.0 }
local COL_ACCENT = { 0.40, 0.90, 0.40, 1.0 }

local ICON_RAIN  = "\xEF\x81\x83"   -- nf-fa-tint U+F043

-- -----------------------------------------------------------------------
-- ICON HELPERS  (MET Norway via jsDelivr CDN)
-- -----------------------------------------------------------------------
local METNO_BASE = "https://cdn.jsdelivr.net/gh/metno/weathericons@main/weather/png/"

local _mtime_cache   = nil
local _mtime_checked = 0

do
    os.execute("mkdir -p " .. ICON_DIR)
    local h = io.popen("stat -c %Y /dev/shm/conky/nws_forecast.json 2>/dev/null")
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
    if not icon_token or icon_token == "" then
        return fetch_metno_icon("clearsky_day")
    end
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
local MONTHS = { "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec" }
local DAYS   = { "Sun","Mon","Tue","Wed","Thu","Fri","Sat" }

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
    local h = io.popen("stat -c %Y /dev/shm/conky/nws_forecast.json 2>/dev/null")
    if not h then return _mtime_cache and os.date("%I:%M %p", _mtime_cache):gsub("^0", "") or "" end
    local t = tonumber(h:read("*l"))
    h:close()
    if t then _mtime_cache = t; _mtime_checked = now end
    return _mtime_cache and os.date("%I:%M %p", _mtime_cache):gsub("^0", "") or ""
end

-- Split "Sunny then Thunderstorms" into two lines at the "then" boundary.
-- Falls back to a character-count word-wrap when no "then" is present.
local function split_forecast(text)
    if not text or text == "" then return "", "" end
    local a, b = text:match("^(.-)%s+[Tt]hen%s+(.+)$")
    if a then
        if #a > 12 then a = a:sub(1, 10) .. ".." end
        if #b > 12 then b = b:sub(1, 10) .. ".." end
        return a, b
    end
    if #text <= 12 then return text, "" end
    -- wrap at last space before char 11
    local cut = text:sub(1, 11):match("^(.*%S)%s") or 10
    local n = type(cut) == "number" and cut or #cut
    local l2 = text:sub(n + 2)
    if #l2 > 12 then l2 = l2:sub(1, 10) .. ".." end
    return text:sub(1, n), l2
end

-- -----------------------------------------------------------------------
-- MAIN DRAW
-- -----------------------------------------------------------------------
local function do_draw(cr)
    cairo_translate(cr, X_OFFSET, Y_OFFSET)
    local fc   = get_forecast() or {}
    local grid = get_grid_info() or { city = "Local", state = "Weather" }

    local y = 20

    -- Header: location left (Rubik), cache update time right (default font)
    local loc = (grid.city or "Local") .. ", " .. (grid.state or "")
    cairo_select_font_face(cr, "Rubik", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 11)
    cairo_set_source_rgba(cr, COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], COL_ACCENT[4])
    cairo_move_to(cr, PAD, y)
    cairo_show_text(cr, loc)
    draw_text(cr, cache_update_time(), WIN_W-PAD, y,  9, COL_DIM,   "right", false)
    y = y + 20

    -- 5-day forecast grid (same layout/sizes as alien-weather-full.lua)
    if #fc > 0 then
        local col_w = (WIN_W - PAD * 2) / DAYS_TO_SHOW
        for i = 1, math.min(DAYS_TO_SHOW, #fc) do
            local d  = fc[i]
            local cx = PAD + (i - 1) * col_w + col_w / 2 + 2

            local dow, date_str = parse_date_strings(d.date)
            draw_text(cr, dow,      cx, y,       10, COL_TEXT,   "center", true)
            draw_text(cr, date_str, cx, y + 14,   8, COL_DIM,    "center", false)

            draw_image(cr, nws_icon_path(d.icon), cx - 18, y + 15, 40, 40)

            local line1, line2 = split_forecast(d.short_fcst)
            draw_text(cr, line1, cx, y + 62, 7, COL_DIM, "center", false)
            if line2 ~= "" then
                draw_text(cr, line2, cx, y + 71, 7, COL_DIM, "center", false)
            end

            local h_val = tonumber(d.temp_high)
            local l_val = tonumber(d.temp_low)
            local pop   = tonumber(d.pop) or 0

            draw_text(cr, (h_val and h_val .. "°" or "-"), cx, y + 87,  11, COL_HIGH,   "center", true)
            draw_text(cr, (l_val and l_val .. "°" or "-"), cx, y + 101, 10, COL_LOW,    "center", false)
            if pop > 0 then
                local icon_str = ICON_RAIN .. " "
                local pop_str  = pop .. "%"
                local ext = get_ext(cr)
                cairo_select_font_face(cr, FONT_NAME, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
                cairo_set_font_size(cr, 8)
                cairo_text_extents(cr, icon_str .. pop_str, ext)
                local x0 = cx - (ext.width / 2 + ext.x_bearing)
                cairo_set_source_rgba(cr, COL_TEXT[1], COL_TEXT[2], COL_TEXT[3], COL_TEXT[4])
                cairo_move_to(cr, x0, y + 115)
                cairo_show_text(cr, icon_str)
                cairo_text_extents(cr, icon_str, ext)
                cairo_set_source_rgba(cr, COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], COL_ACCENT[4])
                cairo_move_to(cr, x0 + ext.x_advance, y + 115)
                cairo_show_text(cr, pop_str)
            else
                draw_text(cr, "-", cx, y + 115, 8, COL_ACCENT, "center", false)
            end
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
    if not ok then print("forecast draw error: " .. tostring(err)) end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
