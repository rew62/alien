-- owm_fetch.lua - OWM current conditions fetcher
-- Self-contained: all HTTP / parse / cache / icon handling in Lua.
-- Architecture mirrors nws_fetch.lua: module-level state + getter functions.
-- v1.0 2026-05-21 @rew62
--
-- Public API
--   conky_owm_fetch()    call via loadall update_func; fetches if cache stale
--   get_current()        returns _current table (nil until first fetch)
--   owm_get(field)       returns tostring of one field, or "N/A"

local HOME = os.getenv("HOME") or ""
package.path = package.path .. ";./?.lua;../?.lua;" .. HOME .. "/.conky/alien/scripts/?.lua"

------------------------------------------------------------------------
-- Config from .env
------------------------------------------------------------------------
local _env = {}
do
    local ef = io.open(HOME .. "/.conky/alien/.env", "r")
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

local OWM_API_KEY = _env.OWM_API_KEY or _env.owm_api_key or ""
local LAT         = _env.LAT         or _env.lat         or "40.7128"
local LON         = _env.LON         or _env.lon         or "-74.0060"
local UNITS       = _env.UNITS       or _env.units       or "imperial"
local LANG        = _env.LANG        or "en"
local CACHE_TTL   = tonumber(_env.CACHE_TTL) or 300
local ICON_SOURCE = _env.ICON_SOURCE or "cdn"
local ALIEN_DIR   = HOME .. "/.conky/alien"

local CACHE_DIR  = "/dev/shm/conky"
local CACHE_JSON = CACHE_DIR .. "/owm_current.json"
local ICON_DIR   = CACHE_DIR .. "/icons"
local LOCK_DIR   = CACHE_DIR .. "/.owm_fetching"
local LOG_FILE   = CACHE_DIR .. "/owm_fetch.log"

------------------------------------------------------------------------
-- JSON
------------------------------------------------------------------------
local cjson = nil
do
    local ok, lib = pcall(require, "cjson")
    if ok then cjson = lib
    else
        local ok2, lib2 = pcall(require, "json")
        if ok2 then cjson = lib2
        else print("owm_fetch: FATAL: no JSON library") end
    end
end

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------
local _current = nil

------------------------------------------------------------------------
-- File helpers
------------------------------------------------------------------------
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function file_age_seconds(path)
    local f = io.open(path, "r")
    if not f then return math.huge end
    f:close()
    local h = io.popen("stat -c %Y " .. path .. " 2>/dev/null")
    if not h then return math.huge end
    local mtime = tonumber(h:read("*l")); h:close()
    if not mtime then return math.huge end
    return os.time() - mtime
end

local function dir_age_seconds(path)
    local h = io.popen("stat -c %Y " .. path .. " 2>/dev/null")
    if not h then return math.huge end
    local mtime = tonumber(h:read("*l")); h:close()
    if not mtime then return math.huge end
    return os.time() - mtime
end

local function mkdir_p(path)
    os.execute("mkdir -p '" .. path .. "' 2>/dev/null")
end

local function mkdir_atomic(path)
    local ret = os.execute("mkdir '" .. path .. "' 2>/dev/null")
    if type(ret) == "boolean" then return ret end
    return ret == 0
end

------------------------------------------------------------------------
-- Time formatting (pure Lua — avoids %-d Lua/glibc incompatibility)
------------------------------------------------------------------------
local function fmt_12h(ts)
    if not ts or ts == 0 then return "" end
    local t = os.date("*t", ts)
    local h = t.hour % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d%s", h, t.min, t.hour < 12 and "a" or "p")
end

------------------------------------------------------------------------
-- Wind helpers
------------------------------------------------------------------------
local function wind_cardinal(deg)
    local dirs = {"N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"}
    return dirs[math.floor((deg * 10 + 112) / 225) % 16 + 1]
end

local function generate_wind_arrow(speed, deg)
    local svg_path = "/dev/shm/owm_wind.svg"
    local png_path = "/dev/shm/owm_wind.png"
    local arrow_deg = (deg + 180) % 360
    local thick = math.min(1 + speed / 3.0, 12)
    local color = speed >= 40 and "#ff0000" or speed >= 15 and "#ffff00" or "white"

    local f = io.open(svg_path, "w")
    if f then
        f:write(string.format(
            '<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' ..
            '<defs><filter id="shadow"><feDropShadow dx="0" dy="1" stdDeviation="1" flood-opacity="0.5"/></filter></defs>' ..
            '<g transform="translate(24,24) rotate(%d)" filter="url(#shadow)">' ..
            '<line x1="0" y1="12" x2="0" y2="-5" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>' ..
            '<polygon points="0,-18 -12,-5 12,-5" fill="%s"/>' ..
            '</g></svg>',
            arrow_deg, color, thick, color))
        f:close()
    end

    os.execute(
        "command -v rsvg-convert >/dev/null 2>&1 && " ..
        "rsvg-convert -w 48 -h 48 '" .. svg_path .. "' -o '" .. png_path .. "' 2>/dev/null || true")

    return svg_path, png_path
end

------------------------------------------------------------------------
-- Icon helpers
------------------------------------------------------------------------
local _METNO = {
    ["01d"] = "clearsky_day",     ["01n"] = "clearsky_night",
    ["02d"] = "fair_day",         ["02n"] = "fair_night",
    ["03d"] = "partlycloudy_day", ["03n"] = "partlycloudy_night",
    ["04d"] = "cloudy",           ["04n"] = "cloudy",
    ["09d"] = "lightrain",        ["09n"] = "lightrain",
    ["10d"] = "rain",             ["10n"] = "rain",
    ["11d"] = "rainandthunder",   ["11n"] = "rainandthunder",
    ["13d"] = "snow",             ["13n"] = "snow",
    ["50d"] = "fog",              ["50n"] = "fog",
}
local _UNI = {
    ["01"]="☀", ["02"]="🌤", ["03"]="⛅", ["04"]="☁",
    ["09"]="🌧", ["10"]="🌦", ["11"]="⛈", ["13"]="❄", ["50"]="🌫",
}

local function cloud_override(data, code)
    local now    = os.time()
    local sr     = (data.sys    and data.sys.sunrise)  or 0
    local ss     = (data.sys    and data.sys.sunset)   or 0
    local clouds = data.clouds  and data.clouds.all
    local rain1  = (data.rain   and data.rain["1h"])   or 0
    local snow1  = (data.snow   and data.snow["1h"])   or 0
    if not clouds or rain1 ~= 0 or snow1 ~= 0 or now < sr or now > ss then return code end
    local c = math.floor(clouds)
    if     c <= 15 then return "01d"
    elseif c <= 40 then return "02d"
    elseif c <= 70 then return "03d"
    else                return "04d"
    end
end

local function ensure_cdn_icon(code)
    mkdir_p(ICON_DIR)
    local path = ICON_DIR .. "/" .. code .. ".png"
    if not file_exists(path) then
        os.execute(string.format(
            "curl -fsS --max-time 8 -o '%s' 'https://openweathermap.org/img/wn/%s@2x.png' 2>/dev/null || true",
            path, code))
    end
end

local function update_current_icon(code)
    local outpng  = ICON_DIR .. "/current.png"
    local loc_dir = ALIEN_DIR .. "/icons"

    local function copy(src)
        if file_exists(src) then
            os.execute(string.format("cp -f '%s' '%s.tmp' && mv -f '%s.tmp' '%s'",
                src, outpng, outpng, outpng))
            return true
        end
        return false
    end

    if ICON_SOURCE == "local" then
        local _ = copy(loc_dir .. "/" .. code .. ".png")
                   or copy(loc_dir .. "/" .. code:gsub("n$","d") .. ".png")
                   or copy(ICON_DIR .. "/" .. code .. ".png")
    else
        local _ = copy(ICON_DIR .. "/" .. code .. ".png")
                   or copy(ICON_DIR .. "/" .. code:gsub("n$","d") .. ".png")
    end
end

------------------------------------------------------------------------
-- Parse OWM JSON → _current table
------------------------------------------------------------------------
local function title_case(s)
    return (s:gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b end))
end

local function parse_owm(data)
    local m = data.main  or {}
    local w = data.wind  or {}
    local s = data.sys   or {}
    local weather = (data.weather and data.weather[1]) or {}

    local temp_unit = UNITS == "metric" and "°C" or "°F"
    local wind_unit = UNITS == "metric" and "kph" or "mph"

    local code = cloud_override(data, weather.icon or "01d")
    ensure_cdn_icon(code)
    update_current_icon(code)

    local speed   = math.floor((w.speed or 0) + 0.5)
    local svg_path, png_path = generate_wind_arrow(speed, w.deg or 0)
    local now = os.time()
    local is_day  = now >= (s.sunrise or 0) and now <= (s.sunset or 0)
    local wid     = weather.id or 800
    local emoji
    if     wid >= 200 and wid < 300 then emoji = "⛈️"
    elseif wid >= 300 and wid < 400 then emoji = "🌦️"
    elseif wid == 500               then emoji = is_day and "🌦️" or "🌧️"
    elseif wid == 511               then emoji = "🌨️"
    elseif wid >= 500 and wid < 600 then emoji = "🌧️"
    elseif wid >= 600 and wid < 700 then emoji = "❄️"
    elseif wid == 771 or wid == 781 then emoji = "🌪️"
    elseif wid >= 700 and wid < 800 then emoji = "🌫️"
    elseif wid == 800               then emoji = is_day and "☀️" or "🌕"  -- 🌙 U+1F319 not in NotoSansSymbols2; 🌕 U+1F315 is
    elseif wid == 801               then emoji = is_day and "⛅" or "☁️"
    elseif wid == 802               then emoji = is_day and "🌤️" or "☁️"
    elseif wid == 803               then emoji = "🌥️"
    elseif wid >= 804               then emoji = "☁️"
    else                                 emoji = "❓"
    end

    return {
        temp       = math.floor((m.temp       or 0) + 0.5),
        feels_like = math.floor((m.feels_like or 0) + 0.5),
        temp_max   = math.floor((m.temp_max   or 0) + 0.5),
        temp_min   = math.floor((m.temp_min   or 0) + 0.5),
        humidity   = m.humidity or 0,
        pressure   = string.format("%.2f", (m.pressure or 0) * 0.02953),
        wind_speed = speed,
        wind_deg   = w.deg or 0,
        wind_card  = wind_cardinal(w.deg or 0),
        wind_unit  = wind_unit,
        temp_unit  = temp_unit,
        desc       = title_case(weather.description or ""),
        icon_owm   = code,
        icon_metno = _METNO[code] or "partlycloudy_day",
        icon_uni   = _UNI[code:sub(1,2)] or "?",
        icon_emoji = emoji,
        wind_svg   = svg_path,
        wind_png   = png_path,
        sunrise    = fmt_12h(s.sunrise),
        sunset     = fmt_12h(s.sunset),
        sunrise_ts = s.sunrise or 0,
        sunset_ts  = s.sunset  or 0,
        lat        = data.coord and data.coord.lat or 0,
        location   = data.name or "Unknown",
        updated    = fmt_12h(now),
        timestamp  = now,
    }
end

------------------------------------------------------------------------
-- HTTP fetch
------------------------------------------------------------------------
local function do_fetch()
    if OWM_API_KEY == "" then
        print("owm_fetch: OWM_API_KEY not set"); return false
    end
    local url = string.format(
        "https://api.openweathermap.org/data/2.5/weather?lat=%s&lon=%s&units=%s&lang=%s&appid=%s",
        LAT, LON, UNITS, LANG, OWM_API_KEY)
    local tmp = CACHE_JSON .. ".tmp"
    local cmd = string.format('curl -fsS --max-time 10 "%s" -o "%s" 2>>"%s"', url, tmp, LOG_FILE)

    local function attempt()
        local r = os.execute(cmd)
        return type(r) == "boolean" and r or r == 0
    end

    if not attempt() and not attempt() then
        print("owm_fetch: fetch failed after retry")
        os.execute("rm -f " .. tmp)
        return false
    end

    local raw = read_file(tmp)
    if not raw or not raw:find('"weather"') then
        print("owm_fetch: invalid API response")
        os.execute("rm -f " .. tmp); return false
    end

    os.execute("mv -f '" .. tmp .. "' '" .. CACHE_JSON .. "'")
    return true
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function conky_owm_fetch()
    mkdir_p(CACHE_DIR)

    -- Warm module state from disk cache (e.g. after conky restart within TTL)
    if not _current and file_exists(CACHE_JSON) then
        local raw = read_file(CACHE_JSON)
        local ok, data = pcall(cjson.decode, raw or "")
        if ok and data and data.weather then
            _current = parse_owm(data)
        end
    end

    if file_age_seconds(CACHE_JSON) < CACHE_TTL then return "" end

    -- Break stale lock left by a crashed caller (curl max-time 10s; 60s is safe)
    if dir_age_seconds(LOCK_DIR) > 60 then
        os.execute("rmdir '" .. LOCK_DIR .. "' 2>/dev/null")
    end

    if not mkdir_atomic(LOCK_DIR) then return "" end

    local ok, err = pcall(function()
        if do_fetch() then
            local raw = read_file(CACHE_JSON)
            local ok2, data = pcall(cjson.decode, raw or "")
            if ok2 and data and data.weather then
                _current = parse_owm(data)
            end
        end
    end)
    if not ok then print("owm_fetch: " .. tostring(err)) end

    os.execute("rmdir '" .. LOCK_DIR .. "' 2>/dev/null")
    return ""
end

function get_current()  return _current end

function owm_get(field)
    if not _current then return "N/A" end
    local v = _current[field]
    return v ~= nil and tostring(v) or "N/A"
end
