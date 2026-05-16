-- complications/wttr_weather.lua
--
-- Arc-style wttr.in temperature complication for the bottom-right corner.
-- The arc is centred at the WIDGET centre and sits inside the dark bezel
-- ring, spanning the bottom-right diagonal (±30° around 45°).
--
-- Visual layout:
--   [LO]  ── dim track ──  ●  ── bright bar ──  [HI]
--                          ↑
--                        56°  (radially outward from dot)
--
-- In CORNER_POS use: { cx = 150, cy = 150, r = 150 }
--
-- Reads /dev/shm/wttr/weather.json (°F), cached per minute.
-- v1.0 2026-05-16 @rew62

local M = {}

local WEATHER_FILE = "/dev/shm/wttr/weather.json"

-- Derive this file's directory so we can find the shared .env
local _DIR = debug.getinfo(1, "S").source:match("@?(.*/)")  or "./"

local _last_fetch    = 0
local FETCH_INTERVAL = 300   -- seconds (5 minutes)

local function weather_file_age()
    local f = io.popen("stat -c %Y " .. WEATHER_FILE .. " 2>/dev/null")
    if not f then return math.huge end
    local s = f:read("*l"); f:close()
    local mtime = tonumber(s)
    if not mtime then return math.huge end   -- file missing
    return os.time() - mtime
end

local function ensure_weather_file()
    -- Only fetch if another process isn't keeping the file fresh
    if weather_file_age() < FETCH_INTERVAL then return end
    -- Throttle our own attempts to once per interval
    local now = os.time()
    if now - _last_fetch < FETCH_INTERVAL then return end
    _last_fetch = now

    -- Read LAT/LON from ../../alien/.env (same location the bash script uses)
    local lat, lon = "40.7128", "-74.0060"
    local ef = io.open(_DIR .. "../../.env", "r")
    if ef then
        for line in ef:lines() do
            local v = line:match("^[Ll][Aa][Tt]=(.+)$"); if v then lat = v end
            v       = line:match("^[Ll][Oo][Nn]=(.+)$"); if v then lon = v end
        end
        ef:close()
    end

    -- Validate before injecting into shell command
    if tonumber(lat) and tonumber(lon) then
        os.execute(
            "mkdir -p /dev/shm/wttr"
            .. " && mkdir /dev/shm/wttr/.fetching 2>/dev/null"
            .. " && (curl -s 'https://wttr.in/"
            .. lat .. "," .. lon .. "?format=j1'"
            .. " -o /dev/shm/wttr/weather.json"
            .. "; rmdir /dev/shm/wttr/.fetching) &"
        )
    end
end

-- Arc spans 30°–60° (30° sweep centred on the 45° diagonal).
-- At r=150 this sits just outside the 143px bezel, entirely within
-- the crescent corner space outside the dial.
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
    ensure_weather_file()
    local f = io.open(WEATHER_FILE, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    -- temp_F (underscore) is current_condition only; hourly uses tempF
    local cur = tonumber(s:match('"temp_F"%s*:%s*"(-?%d+)"'))
    local hi  = tonumber(s:match('"maxtempF"%s*:%s*"(-?%d+)"'))
    local lo  = tonumber(s:match('"mintempF"%s*:%s*"(-?%d+)"'))
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

    -- bottom-right of text flush to the widget corner (300,300) with 4px pad
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
    -- Extending tangentially keeps the numbers "in line" with the arc ends
    -- rather than floating radially above/below them.
    --   LO end (A_LO): arc continues in direction (-sinA, cosA)
    --   HI end (A_HI): arc continues in direction ( sinA,-cosA)
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)

    local GAP = 14   -- pixels past each endpoint

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

    -- LO: past the cold end, continuing the arc direction
    tang_label(A_LO, -math.sin(A_LO),  math.cos(A_LO), string.format("%d", lo or 0))
    -- HI: past the hot end, in the reverse arc direction
    tang_label(A_HI,  math.sin(A_HI), -math.cos(A_HI), string.format("%d", hi or 0))
end

return M
