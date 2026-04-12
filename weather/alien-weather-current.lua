-- alien-weather-current.lua - current conditions Lua/Cairo script
-- data via owm_get() from scripts/owm_fetch.sh
-- v1.1 2026-04-09 @rew62
--
--   ┌──────────────────────────────────────────────────────────────┐
--   │  TEMP   │  ICON  │  Feels like XX°   │  ↑ wind svg          │
--   │  68°    │  [img] │  Humidity   60%   │  NW 28 mph           │
--   ├──────────────────────────────────────────────────────────────┤
--   │  Scattered Clouds                              Updated 1:55p │
--   └──────────────────────────────────────────────────────────────┘
--
-- Public entry point: conky_weather_current()
-- Called from loadall.lua when weather_type == "current"

require 'cairo'

-- -----------------------------------------------------------------------
-- CONFIG  ← tune these after first render
-- -----------------------------------------------------------------------
local CFG = {
    -- Overall dimensions
    WIDGET_W    = 260,      -- total width  px
    WIDGET_H    = 70,       -- main area height px (footer adds FOOTER_H)
    FOOTER_H    = 14,       -- footer strip height px
    OFFSET_X    = 0,        -- left edge on Conky canvas
    OFFSET_Y    = 12,        -- top  edge on Conky canvas

    -- Column widths (must sum to ≤ WIDGET_W - 2*PAD)
    COL_TEMP_W  = 95,       -- temperature column width
    COL_ICON_W  = 60,       -- icon column width
    COL_META_W  = 60,      -- feels like / humidity column width
    COL_WIND_W  = 60,       -- wind column width
    PAD         = 5,        -- outer left/right padding

    -- Icon
    ICON_PX     = 48,       -- icon image size (square)

    -- Wind SVG
    WIND_SVG    = "/dev/shm/owm_wind.svg",   -- fixed path from owm-fetch.lua
    WIND_PNG    = "/dev/shm/owm_wind.png",   -- rsvg-convert output (see notes)
    WIND_PX     = 36,       -- wind arrow display size

    -- Font
    FONT        = cairo_font or "DejaVu Sans",

    -- Font sizes
    SIZE_TEMP   = 48,       -- current temperature  (dominant)
    SIZE_UNIT   = 16,       -- degree symbol / unit (superscript feel)
    SIZE_LABEL  = 10,        -- "Feels like" / "Humidity" labels
    SIZE_VALUE  = 16,       -- feels like / humidity values
    SIZE_WIND   = 10,        -- wind speed + direction text
    SIZE_FOOTER = 12,        -- short forecast + updated time

    -- Background panel
    DRAW_BG     = false,
    BG_RADIUS   = 8,
    COLOR_BG    = { 0.05, 0.07, 0.12, 0.55 },

    -- Dividers
    COLOR_DIV   = { 1.00, 1.00, 1.00, 0.10 },
    DRAW_DIVS   = true,     -- vertical column separators
}

-- Colors
local COL_TEMP   = { 1.00, 1.00, 1.00, 1.00 }  -- bright white for temp
local COL_UNIT   = { 0.75, 0.75, 0.75, 0.90 }  -- dimmer for °F
local COL_LABEL  = { 0.70, 0.75, 0.75, 0.90 }  -- muted blue-grey labels
local COL_VALUE  = { 0.85, 0.85, 0.85, 1.00 }  -- values
local COL_WIND   = { 0.85, 0.85, 0.85, 1.00 }  -- wind text
local COL_FOOTER = { 0.85, 0.85, 0.85, 1.00 }  -- footer desc
local COL_UPDATE = { 0.40, 0.90, 0.40, 0.80 }  -- updated time (accent green)
local COL_HUMID  = { 0.35, 0.75, 1.00, 1.00 }  -- humidity (cool blue)
local COL_FEELS  = { 1.00, 0.65, 0.20, 0.90 }  -- feels like (warm amber)

-- -----------------------------------------------------------------------
-- METNO ICON HELPER
-- -----------------------------------------------------------------------
local ICON_DIR   = "/dev/shm/conky_icons/"
local METNO_BASE = "https://cdn.jsdelivr.net/gh/metno/weathericons@main/weather/png/"

local function fetch_metno_icon(name)
    local path = ICON_DIR .. "metno_" .. name .. ".png"
    local fh = io.open(path, "r")
    if fh then fh:close(); return path end
    os.execute(string.format('curl -sfL "%s" -o "%s" &', METNO_BASE .. name .. ".png", path))
    local fallback = ICON_DIR .. "metno_clearsky_day.png"
    local fb = io.open(fallback, "r")
    if fb then fb:close(); return fallback end
    return path
end

-- -----------------------------------------------------------------------
-- DRAWING HELPERS
-- -----------------------------------------------------------------------
local function set_col(cr, c)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
end

local _ext = nil
local function text_ext(cr, text)
    if not _ext then _ext = cairo_text_extents_t:create() end
    cairo_text_extents(cr, tostring(text), _ext)
    return _ext
end

local function setup_font(cr, size, bold)
    cairo_select_font_face(cr, CFG.FONT,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
end

-- Draw text left-aligned
local function draw_left(cr, text, x, y, size, col, bold)
    setup_font(cr, size, bold)
    set_col(cr, col)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(text))
end

-- Draw text centered on cx
local function draw_center(cr, text, cx, y, size, col, bold)
    setup_font(cr, size, bold)
    set_col(cr, col)
    local e = text_ext(cr, text)
    cairo_move_to(cr, cx - (e.width / 2 + e.x_bearing), y)
    cairo_show_text(cr, tostring(text))
end

-- Draw text right-aligned
local function draw_right(cr, text, x, y, size, col, bold)
    setup_font(cr, size, bold)
    set_col(cr, col)
    local e = text_ext(cr, text)
    cairo_move_to(cr, x - e.width - e.x_bearing, y)
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

local function rounded_rect(cr, x, y, w, h, r)
    if r <= 0 then cairo_rectangle(cr, x, y, w, h); return end
    local pi = math.pi
    cairo_new_sub_path(cr)
    cairo_arc(cr, x+w-r, y+r,   r, -pi/2, 0)
    cairo_arc(cr, x+w-r, y+h-r, r,  0,    pi/2)
    cairo_arc(cr, x+r,   y+h-r, r,  pi/2, pi)
    cairo_arc(cr, x+r,   y+r,   r,  pi,   3*pi/2)
    cairo_close_path(cr)
end

local function vline(cr, x, y1, y2)
    set_col(cr, CFG.COLOR_DIV)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, math.floor(x) + 0.5, y1)
    cairo_line_to(cr, math.floor(x) + 0.5, y2)
    cairo_stroke(cr)
end

local function hline(cr, x1, x2, y)
    set_col(cr, CFG.COLOR_DIV)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, x1, math.floor(y) + 0.5)
    cairo_line_to(cr, x2, math.floor(y) + 0.5)
    cairo_stroke(cr)
end

-- -----------------------------------------------------------------------
-- MAIN DRAW
-- -----------------------------------------------------------------------
local function do_draw(cr)
    -- Guard: owm_get must be available (owm-fetch.lua loaded)
    if not owm_get then
        draw_left(cr, "owm-fetch.lua not loaded", CFG.OFFSET_X + CFG.PAD,
            CFG.OFFSET_Y + 20, 9, COL_VALUE, false)
        return
    end

    -- Pull all values
    local temp       = owm_get("temp")
    local feels_like = owm_get("feels_like")
    local humidity   = owm_get("humidity")
    local wind_speed = owm_get("wind_speed")
    local wind_card  = owm_get("wind_card")
    local wind_unit  = owm_get("wind_unit")
    local desc       = owm_get("desc")
    local icon_metno = owm_get("icon_metno")
    local updated    = owm_get("updated")
    local temp_unit  = owm_get("temp_unit")

    -- Fallback display strings
    temp       = (temp       ~= "N/A" and temp       or "--")
    feels_like = (feels_like ~= "N/A" and feels_like or "--")
    humidity   = (humidity   ~= "N/A" and humidity   or "--")
    wind_speed = (wind_speed ~= "N/A" and wind_speed or "--")
    wind_card  = (wind_card  ~= "N/A" and wind_card  or "--")
    wind_unit  = (wind_unit  ~= "N/A" and wind_unit  or "mph")
    desc       = (desc       ~= "N/A" and desc       or "")
    icon_metno = (icon_metno ~= "N/A" and icon_metno or "partlycloudy_day")
    updated    = (updated    ~= "N/A" and updated    or "")
    temp_unit  = (temp_unit  ~= "N/A" and temp_unit  or "°F")

    local W  = CFG.WIDGET_W
    local H  = CFG.WIDGET_H
    local FH = CFG.FOOTER_H
    local ox = CFG.OFFSET_X
    local oy = CFG.OFFSET_Y
    local P  = CFG.PAD

    -- Background (main + footer)
    if CFG.DRAW_BG then
        set_col(cr, CFG.COLOR_BG)
        rounded_rect(cr, ox, oy, W, H + FH, CFG.BG_RADIUS)
        cairo_fill(cr)
    end

    -- ── Column X positions ────────────────────────────────────────────
    local x_temp = ox + P
    local x_icon = x_temp + CFG.COL_TEMP_W
    local x_meta = x_icon + CFG.COL_ICON_W
    local x_wind = x_meta + CFG.COL_META_W

    -- Column centers
    local cx_temp = x_temp + CFG.COL_TEMP_W / 2
    local cx_icon = x_icon + CFG.COL_ICON_W / 2
    local cx_meta = x_meta + CFG.COL_META_W / 2
    local cx_wind = x_wind + CFG.COL_WIND_W / 2

    -- Vertical center of main area
    local mid_y = oy + H / 2

    -- ── COLUMN 1: Temperature ─────────────────────────────────────────
    -- Large temp centered vertically, unit smaller alongside
    setup_font(cr, CFG.SIZE_TEMP, true)
    local te = text_ext(cr, temp)
    local temp_baseline = mid_y + te.height / 2 - 2
    draw_center(cr, temp, cx_temp, temp_baseline, CFG.SIZE_TEMP, COL_TEMP, true)

    -- Unit superscript-style: top-right of temp
    setup_font(cr, CFG.SIZE_UNIT, false)

    -- Unit: sits top-right of the temp number
    local unit_x = cx_temp + te.width / 2 + 2
    local unit_y = oy + CFG.SIZE_UNIT + 12 
    draw_left(cr, temp_unit, unit_x, unit_y, CFG.SIZE_UNIT, COL_UNIT, false)

    -- ── COLUMN 2: Icon ────────────────────────────────────────────────
    local icon_path = fetch_metno_icon(icon_metno)
    local icon_x = cx_icon - CFG.ICON_PX / 2
    local icon_y = oy + (H - CFG.ICON_PX) / 2
    draw_image(cr, icon_path, icon_x, icon_y, CFG.ICON_PX, CFG.ICON_PX)

    -- ── COLUMN 3: Feels like + Humidity ──────────────────────────────
    local meta_x = x_meta + 6   -- small left indent within column
    local row1_label_y = oy + H * 0.20
    local row1_value_y = oy + H * 0.45
    local row2_label_y = oy + H * 0.65
    local row2_value_y = oy + H * 0.88

    draw_left(cr, "Feels like",          meta_x, row1_label_y, CFG.SIZE_LABEL, COL_LABEL,  false)
    draw_left(cr, feels_like .. temp_unit, meta_x, row1_value_y, CFG.SIZE_VALUE, COL_FEELS,  true)
    draw_left(cr, "Humidity",            meta_x, row2_label_y, CFG.SIZE_LABEL, COL_LABEL,  false)
    draw_left(cr, humidity .. "%",       meta_x, row2_value_y, CFG.SIZE_VALUE, COL_HUMID,  true)

    -- ── COLUMN 4: Wind ───────────────────────────────────────────────
    -- Wind arrow PNG centered top half, text bottom half
    local wind_png = CFG.WIND_PNG
    local wf = io.open(wind_png, "r")
    if wf then
        wf:close()
        local arrow_x = cx_wind - CFG.WIND_PX / 2
        local arrow_y = oy + 4
        draw_image(cr, wind_png, arrow_x, arrow_y, CFG.WIND_PX, CFG.WIND_PX)
    end

    -- Wind text: cardinal + speed on two lines below arrow
    local wind_text_y1 = oy + H * 0.65
    local wind_text_y2 = oy + H * 0.85
    draw_center(cr, wind_card,                   cx_wind, wind_text_y1, CFG.SIZE_WIND, COL_WIND, true)
    draw_center(cr, wind_speed .. " " .. wind_unit, cx_wind, wind_text_y2, CFG.SIZE_WIND, COL_WIND, false)

    -- ── Column dividers ───────────────────────────────────────────────
    if CFG.DRAW_DIVS then
        local dpad = H * 0.12
        vline(cr, x_icon,           oy + dpad, oy + H - dpad)
        vline(cr, x_meta,           oy + dpad, oy + H - dpad)
        vline(cr, x_wind,           oy + dpad, oy + H - dpad)
    end

    -- ── Footer ────────────────────────────────────────────────────────
    hline(cr, ox + P, ox + W - P, oy + H + 1)
    local fy = oy + H + FH - 2
    --draw_left (cr, desc,    ox + P,     fy, CFG.SIZE_FOOTER, COL_FOOTER, false)
    draw_left(cr, "   " .. desc, ox + P, fy, CFG.SIZE_FOOTER, COL_FOOTER, false)
    draw_right(cr, updated, ox + W - P, fy, CFG.SIZE_FOOTER, COL_UPDATE, false)
end

-- -----------------------------------------------------------------------
-- CONKY ENTRY POINT
-- Called by loadall.lua when weather_type == "current"
-- -----------------------------------------------------------------------
function conky_weather_current()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual,  conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    local ok, err = pcall(do_draw, cr)
    if not ok then print("alien-weather-current draw error: " .. tostring(err)) end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
