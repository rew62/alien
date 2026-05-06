-- terminator.lua - Day/Night Terminator Map for Conky. Dotted world map with real-time day/night shading and smooth twilight gradient along the terminator.
-- v1.0 2026-05-04 @rew62

require 'cairo'

local SCRIPT_DIR = (debug.getinfo(1, 'S').source:match("@?(.*/)" ) or "./")

-- ── Display settings ──────────────────────────────────────────────────────
local MAP_X  = 10       -- left edge on desktop
local MAP_Y  = 20       -- top edge on desktop
local MAP_W  = 800      -- map width  (pixels)
--local MAP_H  = 450    -- map height (pixels)
local MAP_H  = MAP_W / 2
local DOT_R  = 1.25     -- dot radius (pixels)

-- true  → map scrolls, terminator curve stays centred (sun pinned to middle)
-- false → map fixed (prime meridian centred), terminator moves
--local SUN_CENTERED = false
local SUN_CENTERED = true

-- ── Colour palette ────────────────────────────────────────────────────────
-- {r, g, b, a}  all values 0-1
local BG     = {0.02,  0.04,  0.13,  0.90}   -- map background
local DAY    = {0.82,  0.92,  1.00,  1.00}   -- bright near-white

--local NIGHT  = {0.07,  0.11,  0.28,  0.55}   -- muted deep navy
--local NIGHT  = {0.12,  0.18,  0.38,  0.70}   -- lighter navy, more visible
--local NIGHT  = {0.10,  0.15,  0.32,  0.65}   -- subtle step up
--local NIGHT  = {0.15,  0.22,  0.45,  0.75}   -- noticeably brighter, more blue
local NIGHT  = {0.15,  0.32,  0.85,  0.85}   -- noticeably brighter, more blue

-- Terminator transition width (in solar-altitude units, ~sin(°))
-- 0.22 ≈ ±6-7° civil+nautical twilight zone
local TWIL_HALF = 0.11   -- half-width of the fade band

-- ── State ─────────────────────────────────────────────────────────────────
local dots_loaded  = false
local world_dots   = {}
local loc_lat      = nil
local loc_lon      = nil

local function load_location()
    if loc_lat then return end
    local env_file = SCRIPT_DIR .. "../.env"
    local f = io.open(env_file, "r")
    if not f then return end
    for line in f:lines() do
        local v = line:match("^LAT=(.+)$")
        if v then loc_lat = tonumber(v) end
        v = line:match("^LON=(.+)$")
        if v then loc_lon = tonumber(v) end
    end
    f:close()
end

-- ── Helpers ───────────────────────────────────────────────────────────────
local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function load_dots()
    if dots_loaded then return end
    dofile(SCRIPT_DIR .. "dots.lua")
    world_dots  = WORLD_DOTS
    dots_loaded = true
end

-- Returns solar declination (radians) and subsolar longitude (degrees).
local function sun_position()
    local d     = os.date("!*t")           -- UTC time
    local yday  = d.yday
    local utc   = d.hour + d.min / 60.0 + d.sec / 3600.0
    -- Approximate solar declination
    local dec   = math.rad(23.45 * math.sin(math.rad(360.0 / 365.0 * (yday - 81))))
    -- Subsolar longitude: sun is overhead at noon UT on the prime meridian
    local lon   = -(utc - 12.0) * 15.0
    return dec, lon
end

-- Sine of solar altitude for a point at (dot_lat°, dot_lon°).
-- Positive = above horizon (day), negative = below (night).
local function sin_altitude(dot_lat, dot_lon, sun_dec, sun_lon)
    local lat_r = math.rad(dot_lat)
    local H     = math.rad(dot_lon - sun_lon)    -- hour angle
    return math.sin(lat_r) * math.sin(sun_dec)
         + math.cos(lat_r) * math.cos(sun_dec) * math.cos(H)
end

-- Map sin_altitude to a 0-1 illumination factor with smooth twilight band.
local function illumination(sa)
    return clamp((sa + TWIL_HALF) / (2.0 * TWIL_HALF), 0.0, 1.0)
end

-- Equirectangular projection: lon/lat → pixel xy.
-- center_lon: the longitude that maps to the horizontal midpoint.
local function to_px(lon, lat, center_lon)
    local rel = ((lon - center_lon) % 360)
    if rel > 180 then rel = rel - 360 end
    local x = MAP_X + (rel + 180.0) / 360.0 * MAP_W
    local y = MAP_Y + (90.0 - lat)  / 180.0 * MAP_H
    return x, y
end

-- ── Main draw hook ─────────────────────────────────────────────────────────
function conky_draw_terminator()
    if conky_window == nil then return end

    load_dots()
    load_location()

    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual,  conky_window.width, conky_window.height
    )
    local cr = cairo_create(cs)

    -- ── Background rectangle ──
    cairo_rectangle(cr, MAP_X, MAP_Y, MAP_W, MAP_H)
    cairo_set_source_rgba(cr, BG[1], BG[2], BG[3], BG[4])
    cairo_fill(cr)

    -- ── Sun position ──
    local sun_dec, sun_lon = sun_position()
    local center_lon = SUN_CENTERED and sun_lon or 0

    -- ── Draw dots ──
    for _, dot in ipairs(world_dots) do
        local dlat, dlon = dot[1], dot[2]
        local sa  = sin_altitude(dlat, dlon, sun_dec, sun_lon)
        local f   = illumination(sa)

        local r = lerp(NIGHT[1], DAY[1], f)
        local g = lerp(NIGHT[2], DAY[2], f)
        local b = lerp(NIGHT[3], DAY[3], f)
        local a = lerp(NIGHT[4], DAY[4], f)

        local x, y = to_px(dlon, dlat, center_lon)
        cairo_arc(cr, x, y, DOT_R, 0, 6.2831853)
        cairo_set_source_rgba(cr, r, g, b, a)
        cairo_fill(cr)
    end

    -- ── Location marker ──
    if loc_lat and loc_lon then
        local lx, ly = to_px(loc_lon, loc_lat, center_lon)
        -- Outer glow
        cairo_arc(cr, lx, ly, 5.5, 0, 6.2831853)
        cairo_set_source_rgba(cr, 0.2, 0.8, 1.0, 0.22)
        cairo_fill(cr)
        -- Ring
        cairo_arc(cr, lx, ly, 4.0, 0, 6.2831853)
        cairo_set_source_rgba(cr, 0.3, 0.9, 1.0, 0.85)
        cairo_set_line_width(cr, 1.2)
        cairo_stroke(cr)
        -- Centre dot
        cairo_arc(cr, lx, ly, 1.8, 0, 6.2831853)
        cairo_set_source_rgba(cr, 0.65, 1.0, 1.0, 1.0)
        cairo_fill(cr)
    end

    -- ── Sun marker ──
    local sun_lat = math.deg(sun_dec)
    local sx, sy  = to_px(sun_lon, sun_lat, center_lon)

    -- Outer glow rings
    local glow = { {12, 0.08}, {8, 0.15}, {5.5, 0.28} }
    for _, g in ipairs(glow) do
        cairo_arc(cr, sx, sy, g[1], 0, 6.2831853)
        cairo_set_source_rgba(cr, 1.0, 0.85, 0.2, g[2])
        cairo_fill(cr)
    end
    -- Core disc
    cairo_arc(cr, sx, sy, 3.5, 0, 6.2831853)
    cairo_set_source_rgba(cr, 1.0, 0.95, 0.55, 1.0)
    cairo_fill(cr)
    -- Hot centre
    cairo_arc(cr, sx, sy, 1.5, 0, 6.2831853)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0)
    cairo_fill(cr)

    -- ── Subtle border ──
    cairo_rectangle(cr, MAP_X, MAP_Y, MAP_W, MAP_H)
    cairo_set_source_rgba(cr, 0.3, 0.5, 0.8, 0.18)
    cairo_set_line_width(cr, 1.0)
    cairo_stroke(cr)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
