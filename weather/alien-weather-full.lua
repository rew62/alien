-- alien-weather-full.lua - full Lua/Cairo script combining NWS forecast and OWM current conditions
-- Data from nws_weather.lua; OWM fetched on file-age timer
-- v1.1 2026-04-09 @rew62
--
-- Public functions (called by loadall.lua):
--   weather_update()       -- NWS fetch (defined in nws_weather.lua)
--   conky_weather_main()   -- draws everything

require 'cairo'

-- -----------------------------------------------------------------------
-- JSON DEPENDENCY FALLBACK
-- -----------------------------------------------------------------------
-- package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua"
package.path = package.path .. ";./?.lua;../?.lua;" .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

local cjson = nil

local ok, lib = pcall(require, "cjson")
  if ok then
    cjson = lib
  else
    local ok2, lib2 = pcall(require, "json")
    if ok2 then
        cjson = lib2
        print("cjson not found, using scripts/json.lua fallback.")
    else
        print("FATAL: no JSON library found")
    end
end

-- -----------------------------------------------------------------------
-- LOAD .env  (parsed as key=value, same as nws_weather.lua)
-- -----------------------------------------------------------------------
local _env = {}
do
    local env_path = os.getenv("HOME") .. "/.conky/alien/.env"
    local ef = io.open(env_path, "r")
    if ef then
        for line in ef:lines() do
            local stripped = line:match("^([^#]*)") or ""
            local k, v = stripped:match("^%s*([%w_]+)%s*=%s*([^%s]+)%s*$")
            if k and v then
                v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
                _env[k] = v
            end
        end
        ef:close()
    end
end

-- -----------------------------------------------------------------------
-- CONFIGURATION
-- -----------------------------------------------------------------------
local OWM_API_KEY   = _env.OWM_API_KEY or ""
local LATITUDE      = _env.LAT         or "40.7128"
local LONGITUDE     = _env.LON         or "-74.0060"
local DAYS_TO_SHOW  = 5
local OWM_UNITS     = "imperial"
local TEMP_UNIT_SYM = "°F"
local OWM_CACHE_MINS = 15        -- minutes between OWM fetches

-- -----------------------------------------------------------------------
-- INTERNAL SETTINGS
-- -----------------------------------------------------------------------
local ICON_DIR   = "/dev/shm/conky_icons/"
local OWM_CACHE  = "/dev/shm/owm_current.json"
local USER_AGENT = "conky-weather-script/1.0"
local WIN_W, PAD = 300, 12
local FONT_NAME  = cairo_font or "DejaVu Sans"

-- Colors (RGBA)
local COL_TEXT   = { 0.85, 0.85, 0.85, 1.0 }
local COL_DIM    = { 0.55, 0.55, 0.55, 1.0 }
local COL_HIGH   = { 1.00, 0.65, 0.20, 1.0 }
local COL_LOW    = { 0.35, 0.75, 1.00, 1.0 }
local COL_ACCENT = { 0.40, 0.90, 0.40, 1.0 }
local COL_SEP    = { 0.30, 0.30, 0.30, 0.7 }

-- -----------------------------------------------------------------------
-- FILE HELPERS
-- -----------------------------------------------------------------------
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function file_age_minutes(path)
    local f = io.open(path, "r")
    if not f then return math.huge end
    f:close()
    local h = io.popen("stat -c %Y " .. path .. " 2>/dev/null")
    if not h then return math.huge end
    local mtime = tonumber(h:read("*l"))
    h:close()
    if not mtime then return math.huge end
    return (os.time() - mtime) / 60
end

-- -----------------------------------------------------------------------
-- OWM CURRENT CONDITIONS
-- File-age throttle -- consistent with nws_weather.lua and owm-fetch.lua
-- Synchronous curl with tmp file to avoid cache corruption on failed fetch
-- -----------------------------------------------------------------------
local _current = nil

local function owm_fetch()
    if file_age_minutes(OWM_CACHE) < OWM_CACHE_MINS then
        -- Cache still fresh -- just parse what we have
        local raw = read_file(OWM_CACHE)
        if not raw then return end
        local ok, data = pcall(cjson.decode, raw)
        if ok and data and data.main then
            _current = {
                temp       = math.floor(data.main.temp + 0.5),
                feels_like = math.floor(data.main.feels_like + 0.5),
                desc       = data.weather[1].description,
                icon       = data.weather[1].icon,
                wind       = math.floor(data.wind.speed + 0.5),
            }
        end
        return
    end

    -- Cache stale -- fetch synchronously with tmp file pattern
    local tmp = OWM_CACHE .. ".tmp"
    local url = string.format(
        "https://api.openweathermap.org/data/2.5/weather?lat=%s&lon=%s&units=%s&appid=%s",
        LATITUDE, LONGITUDE, OWM_UNITS, OWM_API_KEY)
    local cmd = string.format('curl -sf --max-time 15 -A "%s" "%s" -o "%s"',
        USER_AGENT, url, tmp)
    local ret = os.execute(cmd)
    local ok_curl = (type(ret) == "boolean") and ret or (ret == 0)

    if not ok_curl then
        print("alien-weather-full: OWM fetch failed")
        -- Fall back to existing cache if available
        local raw = read_file(OWM_CACHE)
        if not raw then return end
        ret = raw
    else
        -- Validate tmp before promoting to cache
        local raw = read_file(tmp)
        if not raw then return end
        local ok, data = pcall(cjson.decode, raw)
        if not ok or not data or not data.main then
            print("alien-weather-full: OWM response invalid, keeping old cache")
            os.execute("rm -f " .. tmp)
            return
        end
        -- Promote tmp → cache
        os.execute("mv " .. tmp .. " " .. OWM_CACHE)
    end

    -- Parse final cache
    local raw = read_file(OWM_CACHE)
    if not raw then return end
    local ok, data = pcall(cjson.decode, raw)
    if ok and data and data.main then
        _current = {
            temp       = math.floor(data.main.temp + 0.5),
            feels_like = math.floor(data.main.feels_like + 0.5),
            desc       = data.weather[1].description,
            icon       = data.weather[1].icon,
            wind       = math.floor(data.wind.speed + 0.5),
        }
    end
end

-- -----------------------------------------------------------------------
-- ICON HELPERS  (MET Norway via jsDelivr CDN)
-- -----------------------------------------------------------------------
local METNO_BASE = "https://cdn.jsdelivr.net/gh/metno/weathericons@main/weather/png/"

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

local OWM_TO_METNO = {
    ["01d"] = "clearsky_day",      ["01n"] = "clearsky_night",
    ["02d"] = "fair_day",          ["02n"] = "fair_night",
    ["03d"] = "partlycloudy_day",  ["03n"] = "partlycloudy_night",
    ["04d"] = "cloudy",            ["04n"] = "cloudy",
    ["09d"] = "lightrain",         ["09n"] = "lightrain",
    ["10d"] = "rain",              ["10n"] = "rain",
    ["11d"] = "rainandthunder",    ["11n"] = "rainandthunder",
    ["13d"] = "snow",              ["13n"] = "snow",
    ["50d"] = "fog",               ["50n"] = "fog",
}

local function fetch_metno_icon(name)
    os.execute("mkdir -p " .. ICON_DIR)
    local path = ICON_DIR .. "metno_" .. name .. ".png"
    local f = io.open(path, "r")
    if f then f:close(); return path end
    local url = METNO_BASE .. name .. ".png"
    os.execute(string.format('curl -sfL "%s" -o "%s" &', url, path))
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

local function fetch_icon(owm_code)
    local name = OWM_TO_METNO[owm_code] or "partlycloudy_day"
    return fetch_metno_icon(name)
end

-- -----------------------------------------------------------------------
-- DRAWING HELPERS
-- -----------------------------------------------------------------------

-- Reusable extents object -- allocated once, not per draw call
local _text_ext = nil
local function get_ext(cr)
    if not _text_ext then
        _text_ext = cairo_text_extents_t:create()
    end
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
    if cairo_surface_status(surf) ~= 0 then
        cairo_surface_destroy(surf)
        return
    end
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
local MONTHS = {
    "Jan","Feb","Mar","Apr","May","Jun",
    "Jul","Aug","Sep","Oct","Nov","Dec"
}
local DAYS = { "Sun","Mon","Tue","Wed","Thu","Fri","Sat" }

-- "2025-04-21" → "Mon", "Apr 21"
local function parse_date_strings(iso)
    if not iso or iso == "" then return "---", "" end
    local y, m, d = iso:match("(%d%d%d%d)-(%d%d)-(%d%d)")
    if not y then return "---", "" end
    local t = os.time({ year=tonumber(y), month=tonumber(m), day=tonumber(d) })
    local dow = DAYS[tonumber(os.date("%w", t)) + 1]
    local date_str = MONTHS[tonumber(m)] .. " " .. tostring(tonumber(d))
    return dow, date_str
end

-- NWS cache file mtime formatted as 12h update time
local function cache_update_time()
    local h = io.popen("stat -c %Y /dev/shm/nws_forecast.json 2>/dev/null")
    if not h then return "" end
    local t = tonumber(h:read("*l"))
    h:close()
    if not t then return "" end
    return os.date("%I:%M %p", t):gsub("^0", "")
end

-- -----------------------------------------------------------------------
-- MAIN DRAW
-- -----------------------------------------------------------------------
local function do_draw(cr)
    owm_fetch()

    local fc   = get_forecast() or {}
    local grid = get_grid_info() or { city = "Local", state = "Weather" }
    local cur  = _current

    local y = 20

    -- Header: location left, cache update time right
    local loc = (grid.city or "Local") .. ", " .. (grid.state or "")
    draw_text(cr, loc,                PAD,       y, 11, COL_ACCENT, "left",  true)
    draw_text(cr, cache_update_time(), WIN_W-PAD, y,  9, COL_DIM,   "right", false)
    y = y + 20

    -- Current conditions
    if cur then
        draw_text(cr, cur.temp .. TEMP_UNIT_SYM,              PAD, y + 30, 36, COL_TEXT, "left",  true)
        draw_text(cr, cur.desc:gsub("^%l", string.upper),     PAD, y + 46, 10, COL_DIM,  "left",  false)
        draw_text(cr, "Feels like " .. cur.feels_like .. "°", PAD, y + 58,  9, COL_DIM,  "left",  false)
        draw_text(cr, "Wind: " .. (cur.wind or 0) .. " mph",  PAD, y + 70,  9, COL_DIM,  "left",  false)
        draw_image(cr, fetch_icon(cur.icon), WIN_W - 100, y - 15, 70, 70)
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

            -- Day name + date from NWS data (not os.date offset)
            local dow, date_str = parse_date_strings(d.date)
            draw_text(cr, dow,      cx, y,      10, COL_TEXT, "center", true)
            draw_text(cr, date_str, cx, y + 14,  8, COL_DIM,  "center", false)

            -- Icon
            draw_image(cr, nws_icon_path(d.icon), cx - 18, y + 18, 40, 40)

            -- Short forecast
            local short = (d.short_fcst or ""):match("^(.-) then") or d.short_fcst or ""
            if #short > 12 then short = short:sub(1, 10) .. ".." end
            draw_text(cr, short, cx, y + 65, 7, COL_DIM, "center", false)

            -- High / Low / PoP
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
