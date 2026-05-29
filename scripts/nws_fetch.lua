-- nws_fetch.lua - NWS forecast fetcher, shared across multiple callers
-- Atomic-safe: tmp→mv writes + mkdir lock prevents duplicate concurrent fetches
-- v1.5 2026-05-26 @rew62  mtime gate: only re-parse when cache file changes

local env_path = os.getenv("HOME") .. "/.conky/alien/.env"
package.path = package.path .. ";./?.lua;../?.lua;" .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

local _env = {}
do
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

local LATITUDE        = _env.lat or _env.LAT or "40.7128"
local LONGITUDE       = _env.lon or _env.LON or "-74.0060"
local NWS_STATION     = _env.NWS_STATION or nil   -- optional override, e.g. NWS_STATION=KIAD
local USER_AGENT      = "conky-nws-weather/1.0"

local GRID_CACHE_FILE = "/tmp/nws_grid.json"
local FCST_CACHE_FILE = "/dev/shm/nws_forecast.json"
local CURR_CACHE_FILE = "/dev/shm/nws_current.json"
local GRID_CACHE_DAYS = 14
local FCST_CACHE_MINS = 30
local CURR_CACHE_MINS = 10
local DAYS_WANTED     = 5

------------------------------------------------------------------------
-- JSON
------------------------------------------------------------------------
local cjson = nil
local ok, lib = pcall(require, "cjson")
if ok then
    cjson = lib
else
    local ok2, lib2 = pcall(require, "json")
    if ok2 then
        cjson = lib2
    else
        print("FATAL: no JSON library found")
    end
end

------------------------------------------------------------------------
-- File helpers
------------------------------------------------------------------------
local function file_mtime(path)
    local h = io.popen("stat -c %Y " .. path .. " 2>/dev/null")
    if not h then return nil end
    local t = tonumber(h:read("*l")); h:close()
    return t
end

local function file_age_minutes(path)
    local t = file_mtime(path)
    if not t then return math.huge end
    return (os.time() - t) / 60
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
    local cmd = string.format(
        'curl -sfL --max-time 15 -A "%s" "%s" -o "%s"',
        USER_AGENT, url, out_file)
    local ret = os.execute(cmd)
    if type(ret) == "boolean" then return ret end
    return (ret == 0)
end

local function try_mkdir(path)
    local ret = os.execute("mkdir " .. path .. " 2>/dev/null")
    if type(ret) == "boolean" then return ret end
    return (ret == 0)
end

------------------------------------------------------------------------
-- Step 1 – resolve lat/lon → NWS grid (cached, atomic write)
------------------------------------------------------------------------
local function get_grid()
    if file_age_days(GRID_CACHE_FILE) < GRID_CACHE_DAYS then
        local raw = read_file(GRID_CACHE_FILE)
        if raw then
            local ok, data = pcall(cjson.decode, raw)
            if ok and data and data.office then return data end
        end
    end

    local url = string.format("https://api.weather.gov/points/%s,%s", LATITUDE, LONGITUDE)
    local tmp = GRID_CACHE_FILE .. ".tmp"
    if not curl_get(url, tmp) then
        print("nws_fetch: /points fetch failed")
        return nil
    end

    local raw = read_file(tmp)
    if not raw then return nil end

    local ok, data = pcall(cjson.decode, raw)
    if not ok or not data or not data.properties then
        print("nws_fetch: /points parse failed")
        os.execute("rm -f " .. tmp)
        return nil
    end

    local props = data.properties
    local grid = {
        office              = props.gridId,
        gridX               = math.floor(props.gridX + 0.5),
        gridY               = math.floor(props.gridY + 0.5),
        city                = props.relativeLocation
                              and props.relativeLocation.properties
                              and props.relativeLocation.properties.city  or "Unknown",
        state               = props.relativeLocation
                              and props.relativeLocation.properties
                              and props.relativeLocation.properties.state or "",
        forecast_url        = props.forecast,
        obs_stations_url    = props.observationStations,
    }

    -- Atomic write: rm curl tmp, reuse slot for processed object, mv into place
    os.execute("rm -f " .. tmp)
    local f = io.open(tmp, "w")
    if f then
        f:write(cjson.encode(grid))
        f:close()
        os.execute("mv " .. tmp .. " " .. GRID_CACHE_FILE)
    else
        os.execute("rm -f " .. tmp)
    end

    return grid
end

------------------------------------------------------------------------
-- Icon URL parsing (used by both fetch_current_obs and parse_forecast)
------------------------------------------------------------------------
local _SEVERE_ICON = {
    tsra=true, tsra_sct=true, tsra_hi=true,
    blizzard=true, tornado=true, hurricane=true, tropical_storm=true,
}

local function icon_from_url(url)
    if not url then return "unknown" end
    local path = url:match("/[dn][ai][yg][ht]*/(.-)%?") or
                 url:match("/[dn][ai][yg][ht]*/(.-)$")
    if not path or path == "" then return "unknown" end

    local conds = {}
    for segment in path:gmatch("[^/]+") do
        local token, pop_str = segment:match("^([^,]+),?(%d*)")
        if token and token ~= "" then
            conds[#conds + 1] = { token = token, pop = tonumber(pop_str) or 0 }
        end
    end

    if #conds == 0 then return "unknown" end
    if #conds == 1 then return conds[1].token end

    local c2 = conds[2]
    if c2.pop >= 40 or _SEVERE_ICON[c2.token] then
        return c2.token
    end
    return conds[1].token
end

------------------------------------------------------------------------
-- Step 2 – fetch forecast JSON (cached, atomic write, single-fetch lock)
------------------------------------------------------------------------
local function fetch_forecast(grid)
    if file_age_minutes(FCST_CACHE_FILE) < FCST_CACHE_MINS then
        return read_file(FCST_CACHE_FILE)
    end

    local lock = FCST_CACHE_FILE .. ".lock"

    -- Break stale locks left by a crashed caller (curl max-time is 15s; 60s is safe)
    if file_age_minutes(lock) > 1 then
        os.execute("rmdir " .. lock .. " 2>/dev/null")
    end

    -- Atomic lock: mkdir succeeds for exactly one caller; others return existing cache
    if not try_mkdir(lock) then
        return read_file(FCST_CACHE_FILE)
    end

    -- We hold the lock — fetch, validate, promote; release lock in all exit paths
    local url = grid.forecast_url or string.format(
        "https://api.weather.gov/gridpoints/%s/%d,%d/forecast",
        grid.office, grid.gridX, grid.gridY)
    local tmp = FCST_CACHE_FILE .. ".tmp"

    local function do_fetch()
        if curl_get(url, tmp) then
            local raw = read_file(tmp)
            local ok, data = pcall(cjson.decode, raw or "")
            if ok and data and data.properties then
                os.execute("mv " .. tmp .. " " .. FCST_CACHE_FILE)
            else
                print("nws_fetch: forecast response invalid, keeping old cache")
                os.execute("rm -f " .. tmp)
            end
        else
            print("nws_fetch: forecast fetch failed")
            os.execute("rm -f " .. tmp)
        end
    end

    pcall(do_fetch)                              -- pcall ensures lock is always released
    os.execute("rmdir " .. lock .. " 2>/dev/null")

    return read_file(FCST_CACHE_FILE)
end

------------------------------------------------------------------------
-- Step 3 – fetch current observations (cached, atomic write, single-fetch lock)
------------------------------------------------------------------------
local function c_to_f(c)
    if not c then return nil end
    return c * 9 / 5 + 32
end

local function fetch_current_obs(grid)
    if file_age_minutes(CURR_CACHE_FILE) < CURR_CACHE_MINS then
        return read_file(CURR_CACHE_FILE)
    end

    if not grid or not grid.obs_stations_url then
        print("nws_fetch: no observationStations URL in grid cache")
        return read_file(CURR_CACHE_FILE)
    end

    local lock = CURR_CACHE_FILE .. ".lock"
    if file_age_minutes(lock) > 2 then
        os.execute("rmdir " .. lock .. " 2>/dev/null")
    end
    if not try_mkdir(lock) then
        return read_file(CURR_CACHE_FILE)
    end

    local function do_fetch()
        -- Use override station if set, otherwise resolve from grid stations list
        local station_id = NWS_STATION
        if not station_id then
            local stations_tmp = CURR_CACHE_FILE .. ".stations.tmp"
            if not curl_get(grid.obs_stations_url, stations_tmp) then
                print("nws_fetch: observation stations fetch failed")
                os.execute("rm -f " .. stations_tmp)
                return
            end
            local sraw = read_file(stations_tmp)
            os.execute("rm -f " .. stations_tmp)
            local sok, sdata = pcall(cjson.decode, sraw or "")
            if not sok or not sdata or not sdata.features or not sdata.features[1] then
                print("nws_fetch: stations parse failed")
                return
            end
            station_id = sdata.features[1].properties
                         and sdata.features[1].properties.stationIdentifier
            if not station_id then
                print("nws_fetch: no stationIdentifier in response")
                return
            end
        end

        local obs_url = string.format(
            "https://api.weather.gov/stations/%s/observations/latest", station_id)
        local obs_tmp = CURR_CACHE_FILE .. ".obs.tmp"
        if not curl_get(obs_url, obs_tmp) then
            print("nws_fetch: observations fetch failed")
            os.execute("rm -f " .. obs_tmp)
            return
        end
        local oraw = read_file(obs_tmp)
        os.execute("rm -f " .. obs_tmp)
        local ook, odata = pcall(cjson.decode, oraw or "")
        if not ook or not odata or not odata.properties then
            print("nws_fetch: observations parse failed")
            return
        end

        local op = odata.properties
        -- cjson decodes JSON null as userdata, not Lua nil; sanitize to nil
        local function nv(v) return type(v) == "number" and v or nil end
        local temp_c        = nv(op.temperature        and op.temperature.value)
        local dewpoint_c    = nv(op.dewpoint           and op.dewpoint.value)
        local humidity      = nv(op.relativeHumidity   and op.relativeHumidity.value)
        local pressure_pa   = nv(op.barometricPressure and op.barometricPressure.value)
        local wind_speed_ms = nv(op.windSpeed          and op.windSpeed.value)
        local icon_url     = type(op.icon) == "string" and op.icon or ""
        local nws_token    = icon_from_url(icon_url)
        local is_day       = icon_url:find("/day/") ~= nil

        -- feels-like: use heat index when warm, windchill when cold
        local feels_c = nil
        if temp_c and wind_speed_ms then
            local temp_f = c_to_f(temp_c)
            local wind_mph = (wind_speed_ms or 0) * 2.23694
            if temp_f and temp_f <= 50 and wind_mph >= 3 then
                -- wind chill (NWS formula)
                feels_c = (35.74 + 0.6215*temp_f - 35.75*(wind_mph^0.16)
                           + 0.4275*temp_f*(wind_mph^0.16) - 32) * 5/9
            elseif temp_c and dewpoint_c and temp_c >= 27 then
                -- heat index approximation via dewpoint
                local rh = humidity or (100 * math.exp((17.625*dewpoint_c/(243.04+dewpoint_c))
                                                      - (17.625*temp_c/(243.04+temp_c))))
                local tf = c_to_f(temp_c)
                local hi = -42.379 + 2.04901523*tf + 10.14333127*rh
                           - 0.22475541*tf*rh - 0.00683783*tf*tf
                           - 0.05481717*rh*rh + 0.00122874*tf*tf*rh
                           + 0.00085282*tf*rh*rh - 0.00000199*tf*tf*rh*rh
                feels_c = (hi - 32) * 5/9
            else
                feels_c = temp_c
            end
        end

        local current = {
            temp_f       = temp_c        and math.floor(c_to_f(temp_c) * 10 + 0.5) / 10,
            feels_like_f = feels_c       and math.floor(c_to_f(feels_c) * 10 + 0.5) / 10,
            humidity     = humidity      and math.floor(humidity + 0.5),
            pressure_mb  = pressure_pa   and math.floor(pressure_pa / 100 + 0.5),
            wind_mph     = wind_speed_ms and math.floor(wind_speed_ms * 2.23694 * 10 + 0.5) / 10,
            description  = op.textDescription or "",
            icon         = nws_token,
            is_day       = is_day,
            city         = grid.city  or "",
            state        = grid.state or "",
            station      = station_id,
            updated      = os.time(),
        }

        local tmp = CURR_CACHE_FILE .. ".tmp"
        local f = io.open(tmp, "w")
        if f then
            f:write(cjson.encode(current))
            f:close()
            os.execute("mv " .. tmp .. " " .. CURR_CACHE_FILE)
        else
            os.execute("rm -f " .. tmp)
        end
    end

    local _ok, _err = pcall(do_fetch)
    if not _ok then print("nws_fetch: current obs error: " .. tostring(_err)) end
    os.execute("rmdir " .. lock .. " 2>/dev/null")
    return read_file(CURR_CACHE_FILE)
end

------------------------------------------------------------------------
-- Parse forecast JSON
------------------------------------------------------------------------
local NWS_ICON_MAP = {
    skc            = "clear",
    few            = "few_clouds",
    sct            = "scattered_clouds",
    bkn            = "broken_clouds",
    ovc            = "overcast",
    wind_skc       = "windy",
    wind_few       = "windy",
    wind_sct       = "windy_clouds",
    wind_bkn       = "windy_clouds",
    wind_ovc       = "windy_overcast",
    snow           = "snow",
    rain_snow      = "sleet",
    rain_sleet     = "sleet",
    snow_sleet     = "sleet",
    fzra           = "freezing_rain",
    rain_fzra      = "freezing_rain",
    snow_fzra      = "freezing_rain",
    sleet          = "sleet",
    rain           = "rain",
    rain_showers   = "showers",
    rain_showers_hi = "showers",
    tsra           = "thunderstorm",
    tsra_sct       = "thunderstorm",
    tsra_hi        = "thunderstorm",
    tornado        = "tornado",
    hurricane      = "hurricane",
    tropical_storm = "tropical_storm",
    dust           = "dust",
    smoke          = "smoke",
    haze           = "haze",
    hot            = "hot",
    cold           = "cold",
    blizzard       = "blizzard",
    fog            = "fog",
}

local function canonical_icon(nws_token, is_daytime)
    local base = NWS_ICON_MAP[nws_token] or nws_token
    local suffix = is_daytime and "_day" or "_night"
    local sky_icons = { clear=1, few_clouds=1, scattered_clouds=1, broken_clouds=1, overcast=1 }
    if sky_icons[base] then return base .. suffix end
    return base
end

local function parse_wind_speed(str)
    if not str then return 0 end
    local hi = str:match("to (%d+)")
    if hi then return tonumber(hi) end
    return tonumber(str:match("%d+")) or 0
end

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
    local i = 1
    while i <= #periods and #forecast < DAYS_WANTED do
        local p = periods[i]
        local date = p.startTime:sub(1, 10)
        local day_rec = {
            date         = date,
            dow          = p.name,
            temp_high    = nil,
            temp_low     = nil,
            temp_unit    = p.temperatureUnit or "F",
            wind_speed   = 0,
            wind_dir     = "",
            icon         = "",
            icon_url     = "",
            short_fcst   = "",
            detail_day   = "",
            detail_night = "",
            pop_day      = 0,
            pop_night    = 0,
        }

        if p.isDaytime then
            day_rec.temp_high  = math.floor(p.temperature + 0.5)
            day_rec.wind_speed = parse_wind_speed(p.windSpeed)
            day_rec.wind_dir   = p.windDirection or ""
            day_rec.icon       = canonical_icon(icon_from_url(p.icon), true)
            day_rec.icon_url   = p.icon or ""
            day_rec.short_fcst = p.shortForecast or ""
            day_rec.detail_day = p.detailedForecast or ""
            day_rec.pop_day    = (p.probabilityOfPrecipitation
                                  and p.probabilityOfPrecipitation.value) or 0
            local n = periods[i + 1]
            if n and not n.isDaytime then
                day_rec.temp_low     = math.floor(n.temperature + 0.5)
                day_rec.pop_night    = (n.probabilityOfPrecipitation
                                        and n.probabilityOfPrecipitation.value) or 0
                day_rec.detail_night = n.detailedForecast or ""
                i = i + 2
            else
                i = i + 1
            end
        else
            day_rec.dow          = p.name
            day_rec.temp_low     = math.floor(p.temperature + 0.5)
            day_rec.temp_high    = nil
            day_rec.wind_speed   = parse_wind_speed(p.windSpeed)
            day_rec.wind_dir     = p.windDirection or ""
            day_rec.icon         = canonical_icon(icon_from_url(p.icon), false)
            day_rec.icon_url     = p.icon or ""
            day_rec.short_fcst   = p.shortForecast or ""
            day_rec.detail_night = p.detailedForecast or ""
            day_rec.pop_night    = (p.probabilityOfPrecipitation
                                    and p.probabilityOfPrecipitation.value) or 0
            i = i + 1
        end

        day_rec.pop = math.max(day_rec.pop_day or 0, day_rec.pop_night or 0)
        forecast[#forecast + 1] = day_rec
    end
    return forecast
end

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------
local _forecast   = nil
local _grid       = nil
local _current    = nil
local _fcst_mtime = nil   -- mtime when _forecast was last parsed from disk
local _curr_mtime = nil   -- mtime when _current was last decoded from disk

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function weather_update()
    _grid = get_grid()
    if not _grid then
        print("nws_fetch: could not resolve grid")
        return
    end

    -- fetch_forecast handles TTL check and network refresh internally;
    -- only re-parse the JSON when the cache file has actually changed
    local raw = fetch_forecast(_grid)
    local fcst_mtime = file_mtime(FCST_CACHE_FILE)
    if fcst_mtime ~= _fcst_mtime then
        if raw then
            local fc, err = parse_forecast(raw)
            if fc then
                _forecast  = fc
                _fcst_mtime = fcst_mtime
            else
                print("nws_fetch: parse error: " .. tostring(err))
            end
        else
            print("nws_fetch: no forecast data")
        end
    end

    -- Same gate for current observations
    local curr_raw = fetch_current_obs(_grid)
    local curr_mtime = file_mtime(CURR_CACHE_FILE)
    if curr_mtime ~= _curr_mtime then
        if curr_raw then
            local ok, data = pcall(cjson.decode, curr_raw)
            if ok and data then
                _current   = data
                _curr_mtime = curr_mtime
            end
        end
    end
end

function get_forecast()    return _forecast end
function get_grid_info()   return _grid     end
function get_current_obs() return _current  end

function conky_weather_update() weather_update() end

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

function conky_weather_get(day_index, field)
    if not _forecast then weather_update() end
    if not _forecast then return "N/A" end
    local d = _forecast[tonumber(day_index)]
    if not d then return "" end
    local v = d[field]
    if v == nil then return "" end
    return tostring(v)
end

function conky_weather_city()
    if not _grid then return "" end
    return (_grid.city or "Unknown") .. ", " .. (_grid.state or "")
end

-- conky_weather_get_current("temp_f")       → "75.4"
-- conky_weather_get_current("feels_like_f") → "78.0"
-- conky_weather_get_current("humidity")     → "70"
-- conky_weather_get_current("pressure_mb")  → "1017"
-- conky_weather_get_current("station")      → "KIAD"
function conky_weather_get_current(field)
    if not _current then
        if not _grid then weather_update() end
        local curr_raw = _grid and fetch_current_obs(_grid)
        if curr_raw then
            local ok, data = pcall(cjson.decode, curr_raw)
            if ok and data then _current = data end
        end
    end
    if not _current then return "N/A" end
    local v = _current[field]
    if v == nil then return "" end
    return tostring(v)
end

-- Formatted field access for ${lua conky_nws_fmt field} in conky.text
function conky_nws_fmt(field)
    if not _current then return "N/A" end
    if field == "location" then
        return string.upper((_current.city or "") .. ", " .. (_current.state or ""))
    elseif field == "description" then
        return string.upper((_current.description or ""):sub(1, 16))
    elseif field == "temp_f" or field == "feels_like_f" or field == "wind_mph" then
        local v = tonumber(_current[field])
        return v and tostring(math.floor(v + 0.5)) or "N/A"
    elseif field == "updated_time" then
        local t = tonumber(_current.updated)
        if not t then return "" end
        return os.date("%I:%M%p", t):gsub("^0", ""):lower():gsub("am", "a"):gsub("pm", "p")
        -- fallback if %p is empty in locale:
        -- local h = tonumber(os.date("%H", t))
        -- local suffix = h < 12 and "a" or "p"
        -- return os.date("%I:%M", t):gsub("^0", "") .. suffix
    else
        local v = _current[field]
        return v ~= nil and tostring(v) or ""
    end
end
