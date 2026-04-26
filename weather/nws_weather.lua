-- nws_weather.lua - National Weather Service weather fetcher for Conky
-- Free, no API key required; US locations only (api.weather.gov)
-- v1.1 2026-04-09 @rew62
-- HOW IT WORKS (two-step NWS flow):
--   Step 1: GET https://api.weather.gov/points/{lat},{lon}
--           Returns the grid office + gridX/gridY for your location.
--           Result is cached to GRID_CACHE_FILE so it only runs once
--           (or whenever GRID_CACHE_DAYS expires).
--
--   Step 2: GET https://api.weather.gov/gridpoints/{office}/{x},{y}/forecast
--           Returns a 7-day forecast with one block per 12-hour period
--           (Day / Night pairs).  NWS computes true daily high/low
--           server-side from their 2.5km model grid — no math needed.
--
-- Config section --------------------------------------------------------
local env_path = os.getenv("HOME") .. "/.conky/alien/.env"
-- package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua"
package.path = package.path .. ";./?.lua;../?.lua;" .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

local _env = {}
do
    local ef = io.open(env_path, "r")
    if ef then
        for line in ef:lines() do
            -- Strip inline comments and whitespace, then match key=value
            local stripped = line:match("^([^#]*)") or ""
            local k, v = stripped:match("^%s*([%w_]+)%s*=%s*([^%s]+)%s*$")
            if k and v then
                -- Strip optional surrounding quotes
                v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
                _env[k] = v
            end
        end
        ef:close()
    end
end

local LATITUDE        = _env.lat or _env.LAT or "40.7128"
local LONGITUDE       = _env.lon or _env.LON or "-74.0060"
local USER_AGENT      = "conky-nws-weather/1.0"   -- NWS requires a UA string

local GRID_CACHE_FILE = "/tmp/nws_grid.json"        -- survives reboots (rarely changes)
local FCST_CACHE_FILE = "/dev/shm/nws_forecast.json" -- RAM fs, fast, cleared on reboot
local GRID_CACHE_DAYS = 14                         -- re-resolve grid every N days
local FCST_CACHE_MINS = 30                         -- re-fetch forecast every N mins
local DAYS_WANTED     = 5                          -- forecast days to keep

-- End config ------------------------------------------------------------

--local cjson = require("cjson")
-- -----------------------------------------------------------------------
-- JSON DEPENDENCY FALLBACK
-- -----------------------------------------------------------------------
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

------------------------------------------------------------------------
-- File / cache helpers
------------------------------------------------------------------------

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

local function file_age_days(path)
    return file_age_minutes(path) / 1440
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function curl_get(url, out_file)
    -- Returns true on success.  NWS requires a User-Agent header.
    local cmd = string.format(
        'curl -sfL --max-time 15 -A "%s" "%s" -o "%s"',
        USER_AGENT, url, out_file
    )
    local ret = os.execute(cmd)
    -- Lua 5.1 returns exit code; Lua 5.2+ returns true/false
    if type(ret) == "boolean" then return ret end
    return (ret == 0)
end

------------------------------------------------------------------------
-- Step 1 – resolve lat/lon → NWS grid (cached)
------------------------------------------------------------------------

local function get_grid()
    -- Return cached grid if fresh enough
    if file_age_days(GRID_CACHE_FILE) < GRID_CACHE_DAYS then
        local raw = read_file(GRID_CACHE_FILE)
        if raw then
            local ok, data = pcall(cjson.decode, raw)
            if ok and data and data.office then
                return data
            end
        end
    end

    -- Fetch from /points endpoint
    local url = string.format("https://api.weather.gov/points/%s,%s",
                               LATITUDE, LONGITUDE)
    local tmp = GRID_CACHE_FILE .. ".tmp"
    if not curl_get(url, tmp) then
        print("nws_weather: /points fetch failed")
        return nil
    end

    local raw = read_file(tmp)
    if not raw then return nil end

    local ok, data = pcall(cjson.decode, raw)
    if not ok or not data or not data.properties then
        print("nws_weather: /points parse failed")
        return nil
    end

    local props = data.properties
    local grid = {
        office    = props.gridId,                   -- e.g. "LWX"
        gridX     = math.floor(props.gridX + 0.5),  -- cjson decodes ints as floats
        gridY     = math.floor(props.gridY + 0.5),  -- force to integer
        city      = props.relativeLocation
                    and props.relativeLocation.properties
                    and props.relativeLocation.properties.city  or "Unknown",
        state     = props.relativeLocation
                    and props.relativeLocation.properties
                    and props.relativeLocation.properties.state or "",
        forecast_url = props.forecast,     -- full URL, use directly
    }

    -- Persist grid cache (write our processed grid table, not the raw NWS JSON)
    local f = io.open(GRID_CACHE_FILE, "w")
    if f then
        f:write(cjson.encode(grid))
        f:close()
    end
    -- Clean up the tmp file
    os.execute("rm -f " .. tmp)

    return grid
end

------------------------------------------------------------------------
-- Step 2 – fetch forecast JSON (cached)
------------------------------------------------------------------------

local function fetch_forecast(grid)
    if file_age_minutes(FCST_CACHE_FILE) >= FCST_CACHE_MINS then
        -- Build URL either from cached forecast_url or construct it
        local url = grid.forecast_url or string.format(
            "https://api.weather.gov/gridpoints/%s/%d,%d/forecast",
            grid.office, grid.gridX, grid.gridY
        )
        if not curl_get(url, FCST_CACHE_FILE) then
            print("nws_weather: forecast fetch failed")
        end
    end
    return read_file(FCST_CACHE_FILE)
end

------------------------------------------------------------------------
-- Parse forecast JSON
--
-- NWS /forecast returns "periods" – alternating Day / Night blocks.
-- Each period has:
--   name           "Monday", "Monday Night", "Tuesday", etc.
--   startTime      ISO-8601
--   isDaytime      true / false
--   temperature    integer (already the correct daily high or nightly low)
--   temperatureUnit "F" or "C"
--   windSpeed      "10 mph"  (string – we parse the number out)
--   windDirection  "SW"
--   shortForecast  "Mostly Cloudy"
--   detailedForecast (long string)
--   probabilityOfPrecipitation { value: N }   (may be null)
--   icon           URL like "https://api.weather.gov/icons/land/day/rain,40?size=medium"
------------------------------------------------------------------------

-- Pull the dominant condition token from the NWS icon URL.
-- NWS icon URL formats:
--   .../day/bkn?size=medium                      (single condition)
--   .../day/bkn/rain_showers,30?size=medium      (two conditions, second wins)
--   .../day/rain_showers,40/bkn?size=medium      (two conditions, last wins)
-- We always take the LAST condition token as it represents the dominant weather.
-- The embedded ,pop number is stripped.
local function icon_from_url(url)
    if not url then return "unknown" end
    -- Collect all condition tokens between /day/ or /night/ and the ?query
    local path = url:match("/[dn][ai][yg][ht]*/(.-)%?") or
                 url:match("/[dn][ai][yg][ht]*/(.-)$")
    if not path or path == "" then return "unknown" end
    -- Split on / to get individual condition segments, take the last one
    local last = "unknown"
    for segment in path:gmatch("[^/]+") do
        -- Strip embedded probability number e.g. "rain_showers,30" -> "rain_showers"
        local token = segment:match("^([^,]+)")
        if token and token ~= "" then last = token end
    end
    return last
end

-- Map NWS icon token → a short canonical name usable by your Conky theme
-- (extend this table to match whatever icon set you use)
local NWS_ICON_MAP = {
    skc           = "clear",
    few           = "few_clouds",
    sct           = "scattered_clouds",
    bkn           = "broken_clouds",
    ovc           = "overcast",
    wind_skc      = "windy",
    wind_few      = "windy",
    wind_sct      = "windy_clouds",
    wind_bkn      = "windy_clouds",
    wind_ovc      = "windy_overcast",
    snow          = "snow",
    rain_snow     = "sleet",
    rain_sleet    = "sleet",
    snow_sleet    = "sleet",
    fzra          = "freezing_rain",
    rain_fzra     = "freezing_rain",
    snow_fzra     = "freezing_rain",
    sleet         = "sleet",
    rain          = "rain",
    rain_showers  = "showers",
    rain_showers_hi = "showers",
    tsra          = "thunderstorm",
    tsra_sct      = "thunderstorm",
    tsra_hi       = "thunderstorm",
    tornado       = "tornado",
    hurricane     = "hurricane",
    tropical_storm= "tropical_storm",
    dust          = "dust",
    smoke         = "smoke",
    haze          = "haze",
    hot           = "hot",
    cold          = "cold",
    blizzard      = "blizzard",
    fog           = "fog",
}

local function canonical_icon(nws_token, is_daytime)
    local base = NWS_ICON_MAP[nws_token] or nws_token
    local suffix = is_daytime and "_day" or "_night"
    -- Only add suffix for sky-condition icons where day/night matters
    local sky_icons = {
        clear=1, few_clouds=1, scattered_clouds=1,
        broken_clouds=1, overcast=1
    }
    if sky_icons[base] then
        return base .. suffix
    end
    return base
end

-- Parse "10 mph" → 10
local function parse_wind_speed(str)
    if not str then return 0 end
    -- handle ranges like "10 to 15 mph" → take the higher value
    local hi = str:match("to (%d+)")
    if hi then return tonumber(hi) end
    return tonumber(str:match("%d+")) or 0
end

-- Pair up Day + Night periods into unified day records
local function parse_forecast(raw_json)
    local ok, data = pcall(cjson.decode, raw_json)
    if not ok or not data or not data.properties then
        return nil, "JSON parse failed or missing properties"
    end

    local periods = data.properties.periods
    if not periods or #periods == 0 then
        return nil, "No forecast periods in response"
    end

    local forecast = {}
    local today = os.date("%Y-%m-%d")
    local i = 1

    while i <= #periods and #forecast < DAYS_WANTED do
        local p = periods[i]

        -- Extract calendar date from ISO-8601 startTime
        local date = p.startTime:sub(1, 10)

        -- Build a day record.  NWS alternates Day then Night; but at the
        -- start of the feed the first period might be "Tonight" (isDaytime=false)
        -- if it's already afternoon.  We handle both cases.

        local day_rec = {
            date        = date,
            dow         = p.name,          -- "Monday", "This Afternoon", etc.
            temp_high   = nil,
            temp_low    = nil,
            temp_unit   = p.temperatureUnit or "F",
            wind_speed  = 0,
            wind_dir    = "",
            icon        = "",   -- canonical token e.g. "rain", "broken_clouds_day"
            icon_url    = "",   -- raw NWS URL, usable directly in ${image} via curl
            short_fcst  = "",
            detail_day  = "",
            detail_night= "",
            pop_day     = 0,
            pop_night   = 0,
        }

        if p.isDaytime then
            -- Daytime period
            day_rec.temp_high  = math.floor(p.temperature + 0.5)
            day_rec.wind_speed = parse_wind_speed(p.windSpeed)
            day_rec.wind_dir   = p.windDirection or ""
            day_rec.icon       = canonical_icon(icon_from_url(p.icon), true)
            day_rec.icon_url   = p.icon or ""
            day_rec.short_fcst = p.shortForecast or ""
            day_rec.detail_day = p.detailedForecast or ""
            day_rec.pop_day    = (p.probabilityOfPrecipitation
                                  and p.probabilityOfPrecipitation.value) or 0

            -- Peek ahead for the matching night period
            local n = periods[i + 1]
            if n and not n.isDaytime then
                day_rec.temp_low    = math.floor(n.temperature + 0.5)
                day_rec.pop_night   = (n.probabilityOfPrecipitation
                                       and n.probabilityOfPrecipitation.value) or 0
                day_rec.detail_night = n.detailedForecast or ""
                i = i + 2   -- consumed both periods
            else
                i = i + 1
            end
        else
            -- Feed starts with a night / "Tonight" period (afternoon fetch)
            day_rec.dow        = p.name    -- "Tonight", "This Afternoon", etc.
            day_rec.temp_low   = math.floor(p.temperature + 0.5)
            day_rec.temp_high  = nil       -- no daytime high available
            day_rec.wind_speed = parse_wind_speed(p.windSpeed)
            day_rec.wind_dir   = p.windDirection or ""
            day_rec.icon       = canonical_icon(icon_from_url(p.icon), false)
            day_rec.icon_url   = p.icon or ""
            day_rec.short_fcst = p.shortForecast or ""
            day_rec.detail_night = p.detailedForecast or ""
            day_rec.pop_night  = (p.probabilityOfPrecipitation
                                  and p.probabilityOfPrecipitation.value) or 0
            i = i + 1
        end

        -- Max pop across day+night for a single "chance of rain" number
        day_rec.pop = math.max(day_rec.pop_day or 0, day_rec.pop_night or 0)

        forecast[#forecast + 1] = day_rec
    end

    return forecast
end

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------

local _forecast = nil
local _grid     = nil

------------------------------------------------------------------------
-- Public: call from lua_startup_hook or a timed conky function
------------------------------------------------------------------------

function weather_update()
    _grid = get_grid()
    if not _grid then
        print("nws_weather: could not resolve grid - get_grid() returned nil")
        return
    end

    local raw = fetch_forecast(_grid)
    if not raw then
        print("nws_weather: no forecast data")
        return
    end

    local fc, err = parse_forecast(raw)
    if not fc then
        print("nws_weather: parse error: " .. tostring(err))
        return
    end

    _forecast = fc
end

function get_forecast()    return _forecast end
function get_grid_info()   return _grid     end  -- accessor; get_grid() is the local resolver

------------------------------------------------------------------------
-- Conky text helpers
------------------------------------------------------------------------

-- Full line:  ${lua weather_line 1}
-- "Today     Hi: 68°F  Lo: 45°F  Rain: 30%  Mostly Cloudy"
function conky_weather_line(day_index)
    if not _forecast then weather_update() end
    if not _forecast then return "Weather unavailable" end
    local d = _forecast[tonumber(day_index)]
    if not d then return "" end
    local hi = d.temp_high and string.format("%3d", d.temp_high) or " N/A"
    local lo = d.temp_low  and string.format("%3d", d.temp_low)  or " N/A"
    return string.format("%-17s Hi:%s°%s  Lo:%s°%s  Rain:%3d%%  %s",
        d.dow, hi, d.temp_unit, lo, d.temp_unit, d.pop, d.short_fcst)
end

-- Individual field:  ${lua weather_get 1 temp_high}
-- Valid fields: date dow temp_high temp_low temp_unit wind_speed wind_dir
--               icon short_fcst detail_day detail_night pop pop_day pop_night
function conky_weather_get(day_index, field)
    if not _forecast then weather_update() end
    if not _forecast then return "N/A" end
    local d = _forecast[tonumber(day_index)]
    if not d then return "" end
    local v = d[field]
    if v == nil then return "" end
    return tostring(v)
end

-- City name:  ${lua weather_city}
function conky_weather_city()
    if not _grid then return "" end
    return (_grid.city or "Unknown") .. ", " .. (_grid.state or "")
end

-- Wrapper
function conky_weather_update()
    weather_update()
end

------------------------------------------------------------------------
-- Standalone self-test
-- Run:  lua nws_weather.lua [forecast_cache.json]
-- Fetches live data if no file given (requires curl + internet access)
------------------------------------------------------------------------

if not conky_parse then
    print("=== NWS Weather Self-Test ===")

    if arg and arg[1] then
        -- Use a local JSON file
        local raw = read_file(arg[1])
        if not raw then
            print("Cannot read: " .. arg[1])
            os.exit(1)
        end
        local fc, err = parse_forecast(raw)
        if not fc then
            print("Parse error: " .. tostring(err))
            os.exit(1)
        end
        print(string.rep("-", 90))
        print(string.format("%-17s  %4s  %4s  %4s  %-22s  %s",
            "Period", "High", "Low", "Rain", "Icon token", "Short Forecast"))
        print(string.rep("-", 90))
        for _, d in ipairs(fc) do
            local hi = d.temp_high and tostring(d.temp_high) or "---"
            local lo = d.temp_low  and tostring(d.temp_low)  or "---"
            print(string.format("%-17s  %4s  %4s  %3d%%  %-22s  %s",
                d.dow, hi, lo, d.pop, d.icon, d.short_fcst))
            -- Show the raw icon URL on the next line, indented
            if d.icon_url and d.icon_url ~= "" then
                print(string.format("  icon_url: %s", d.icon_url))
            end
        end
    else
        -- Live fetch
        print("Resolving grid for " .. LATITUDE .. "," .. LONGITUDE .. "...")
        weather_update()
        if not _forecast then
            print("Failed.  Check your internet connection / coordinates.")
            os.exit(1)
        end
        print("Grid: " .. (_grid.office or "?") ..
              " " .. tostring(_grid.gridX) .. "," .. tostring(_grid.gridY))
        print("City: " .. conky_weather_city())
        print(string.rep("-", 90))
        print(string.format("%-17s  %4s  %4s  %4s  %-22s  %s",
            "Period", "High", "Low", "Rain", "Icon token", "Short Forecast"))
        print(string.rep("-", 90))
        for _, d in ipairs(_forecast) do
            local hi = d.temp_high and tostring(d.temp_high) or "---"
            local lo = d.temp_low  and tostring(d.temp_low)  or "---"
            print(string.format("%-17s  %4s  %4s  %3d%%  %-22s  %s",
                d.dow, hi, lo, d.pop, d.icon, d.short_fcst))
            if d.icon_url and d.icon_url ~= "" then
                print(string.format("  icon_url: %s", d.icon_url))
            end
        end
    end
end

------------------------------------------------------------------------
-- USAGE NOTES
--
-- 1. In your conky.conf:
--      lua_load = "~/.conky/nws_weather.lua"
--      lua_startup_hook = "weather_update"
--
-- 2. In conky.text:
--      ${lua weather_city}
--      ${lua weather_line 1}    -- first forecast period (Today or Tonight)
--      ${lua weather_line 2}    -- second period
--      -- or pick individual fields:
--      ${lua weather_get 1 temp_high}
--      ${lua weather_get 1 temp_low}
--      ${lua weather_get 1 icon}        -- canonical token e.g. "rain", "broken_clouds_day"
--      ${lua weather_get 1 icon_url}    -- full NWS URL, fetch with curl for ${image}
--      ${lua weather_get 1 short_fcst}
--      ${lua weather_get 1 wind_speed} ${lua weather_get 1 wind_dir}
--      ${lua weather_get 1 pop}
--
-- 3. The grid is cached for 14 days (GRID_CACHE_FILE).
--    The forecast is re-fetched every 30 minutes (FCST_CACHE_FILE).
--    NWS updates forecasts roughly every hour.
--
-- 4. NWS returns true model-computed daily highs and lows — no averaging
--    or guesswork needed.  Temperatures match weather.gov exactly.
--
-- 5. Two icon fields are provided:
--    icon     = canonical token (e.g. "rain", "tsra", "few_clouds_day")
--               map to your local image files in your drawing lua.
--    icon_url = full NWS URL e.g. "https://api.weather.gov/icons/land/day/bkn?size=medium"
--               fetch once with curl and cache locally, or use directly
--               if your Conky lua drawing code can fetch URLs.
------------------------------------------------------------------------
