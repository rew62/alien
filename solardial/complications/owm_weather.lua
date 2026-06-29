-- complications/owm_weather.lua
--
-- Arc-style temperature complication using OWM as the data source.
-- Visually identical to temperature.lua; replaces wttr.in with the
-- OpenWeatherMap current-weather endpoint.
--
-- Cache: /dev/shm/owm/owm_current.json
-- Arc:   bottom-right corner, 30°–60° sweep, centred on 45° diagonal.
--
-- In CORNER_POS use: { cx = 150, cy = 150, r = 150 }
-- v1.0 2026-05-16 @rew62

local M = {}

local CACHE_DIR  = "/dev/shm/conky"
local CACHE_FILE = CACHE_DIR .. "/owm_current.json"
local LOCK_DIR   = CACHE_DIR .. "/.fetching"

-- Safety: ensure cache dir exists at module load
os.execute("mkdir -p " .. CACHE_DIR)

local _DIR = debug.getinfo(1, "S").source:match("@?(.*/)")  or "./"

local _last_fetch    = 0
local FETCH_INTERVAL = 300   -- seconds (5 minutes)

local function file_age(path)
    local f = io.popen("stat -c %Y " .. path .. " 2>/dev/null")
    if not f then return math.huge end
    local s = f:read("*l"); f:close()
    local mtime = tonumber(s)
    if not mtime then return math.huge end
    return os.time() - mtime
end

local function ensure_cache()
    if file_age(CACHE_FILE) < FETCH_INTERVAL then return end
    local now = os.time()
    if now - _last_fetch < FETCH_INTERVAL then return end
    _last_fetch = now

    local lat, lon, apikey = "40.7128", "-74.0060", nil
    local ef = io.open(_DIR .. "../../.env", "r")
    if ef then
        for line in ef:lines() do
            local v
            v = line:match("^LAT=(.+)$");         if v then lat    = v:gsub('"', '') end
            v = line:match("^LON=(.+)$");         if v then lon    = v:gsub('"', '') end
            v = line:match("^OWM_API_KEY=(.+)$"); if v then apikey = v:gsub('"', '') end
        end
        ef:close()
    end

    -- Validate: lat/lon numeric, apikey hex-only (32 chars)
    if not (tonumber(lat) and tonumber(lon)) then return end
    if not (apikey and apikey:match("^%x+$")) then return end

    os.execute(
        "mkdir " .. LOCK_DIR .. " 2>/dev/null"
        .. " && (curl -s 'https://api.openweathermap.org/data/2.5/weather"
        .. "?lat=" .. lat .. "&lon=" .. lon
        .. "&appid=" .. apikey .. "&units=imperial'"
        .. " -o " .. CACHE_FILE
        .. "; rmdir " .. LOCK_DIR .. ") &"
    )
end

-- Arc spans 30°–60° (30° sweep centred on the 45° diagonal).
-- Cairo screen coords: 0 = right (3-o'clock), clockwise positive.
-- 30° = upper-right end  → HIGH temp
-- 60° = lower-left  end  → LOW  temp
local A_HI  = math.pi / 6        -- 30°  high end
local A_LO  = math.pi / 3        -- 60°  low  end
local SWEEP = A_LO - A_HI        -- 30° = π/6

local cached_cur, cached_hi, cached_lo
local cache_minute = -1

local function read_weather()
    local m = tonumber(os.date("%M"))
    if m == cache_minute and cached_cur then
        return cached_cur, cached_hi, cached_lo
    end
    ensure_cache()
    local f = io.open(CACHE_FILE, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    -- OWM returns unquoted numbers; "temp" appears before "temp_min"/"temp_max"
    local cur = tonumber(s:match('"temp"%s*:%s*([%-0-9%.]+)'))
    local hi  = tonumber(s:match('"temp_max"%s*:%s*([%-0-9%.]+)'))
    local lo  = tonumber(s:match('"temp_min"%s*:%s*([%-0-9%.]+)'))
    if cur then cur = math.floor(cur + 0.5) end
    if hi  then hi  = math.floor(hi  + 0.5) end
    if lo  then lo  = math.floor(lo  + 0.5) end
    cached_cur, cached_hi, cached_lo = cur, hi, lo
    cache_minute = m
    return cur, hi, lo
end

function M.draw(cr, cx, cy, r)
    cairo_new_path(cr)

    local cur, hi, lo = read_weather()
    if not cur then return end

    local pct = 0.5
    if hi and lo and hi ~= lo then
        pct = math.max(0, math.min(1, (cur - lo) / (hi - lo)))
    end

    -- dot sits between A_LO (cold/left) and A_HI (hot/right)
    -- pct=0 → dot at A_LO,  pct=1 → dot at A_HI
    local dot_a = A_LO - SWEEP * pct

    -- ── full arc background (bright, full span) ───────────────────────────
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, A_HI, A_LO)
    cairo_set_line_width(cr, 10)
    cairo_set_source_rgba(cr, 0.55, 0.78, 1.0, 0.14)
    cairo_stroke(cr)

    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, A_HI, A_LO)
    cairo_set_line_width(cr, 5)
    cairo_set_source_rgba(cr, 0.70, 0.87, 1.0, 0.96)
    cairo_stroke(cr)

    -- ── dim overlay from dot to HI end (unfilled portion) ────────────────
    if pct < 0.995 then
        cairo_new_sub_path(cr)
        cairo_arc(cr, cx, cy, r, A_HI, dot_a)
        cairo_set_line_width(cr, 5)
        cairo_set_source_rgba(cr, 0.10, 0.15, 0.35, 0.72)
        cairo_stroke(cr)
    end

    -- ── white dot at current position ─────────────────────────────────────
    local dot_x = cx + math.cos(dot_a) * r
    local dot_y = cy + math.sin(dot_a) * r
    cairo_new_sub_path(cr)
    cairo_arc(cr, dot_x, dot_y, 3, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_fill(cr)

    -- ── current temp — anchored to the bottom-right corner ──────────────
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 20)
    local ts = string.format("%d\xc2\xb0", cur)
    local te = cairo_text_extents_t:create()
    cairo_text_extents(cr, ts, te)

    local tx = (cx * 2) - 4 - (te.width  + te.x_bearing)
    local ty = (cy * 2) - 19 - (te.height + te.y_bearing)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.96)
    cairo_move_to(cr, tx, ty)
    cairo_show_text(cr, ts)

    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)
    local tl = cairo_text_extents_t:create()
    cairo_text_extents(cr, "TEMP", tl)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.70)
    cairo_move_to(cr, (cx * 2) - 6 - (tl.width + tl.x_bearing), ty + 13)
    cairo_show_text(cr, "TEMP")

    -- ── lo / hi labels — tangentially extended past each arc endpoint ─────
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)

    local GAP = 14

    local function tang_label(angle, tan_dx, tan_dy, str)
        local e = cairo_text_extents_t:create()
        cairo_text_extents(cr, str, e)
        local ex = cx + math.cos(angle) * r + tan_dx * GAP
        local ey = cy + math.sin(angle) * r + tan_dy * GAP
        cairo_set_source_rgba(cr, 0.65, 0.80, 1, 0.82)
        cairo_move_to(cr,
            ex - (e.width  / 2 + e.x_bearing),
            ey - (e.height / 2 + e.y_bearing))
        cairo_show_text(cr, str)
    end

    tang_label(A_LO, -math.sin(A_LO),  math.cos(A_LO), string.format("%d", lo or 0))
    tang_label(A_HI,  math.sin(A_HI), -math.cos(A_HI), string.format("%d", hi or 0))
end

return M
