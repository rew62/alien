-- draw_owm_current_top.lua - OWM current conditions, horizontal strip layout
-- Data via owm_get() from scripts/owm_fetch.lua
-- v1.0 2026-05-21 @rew62
--
--   ┌──────────────────────────────────────────────────────────────┐
--   │  TEMP   │  ICON  │  Feels like XX°   │  ↑ wind svg          │
--   │  68°    │  [img] │  Humidity   60%   │  NW 28 mph           │
--   ├──────────────────────────────────────────────────────────────┤
--   │  Scattered Clouds                              Updated 1:55p │
--   └──────────────────────────────────────────────────────────────┘

require 'cairo'

------------------------------------------------------------------------
-- Metno icon helper
------------------------------------------------------------------------
local METNO_CACHE = "/dev/shm/conky/icons/"
local METNO_BASE  = "https://cdn.jsdelivr.net/gh/metno/weathericons@main/weather/png/"

local function fetch_metno_icon(name)
    local path = METNO_CACHE .. "metno_" .. name .. ".png"
    local fh = io.open(path, "r")
    if fh then fh:close(); return path end
    os.execute(string.format('mkdir -p "%s" && curl -sfL "%s" -o "%s" &',
        METNO_CACHE, METNO_BASE .. name .. ".png", path))
    local fallback = METNO_CACHE .. "metno_clearsky_day.png"
    local fb = io.open(fallback, "r")
    if fb then fb:close(); return fallback end
    return path
end

------------------------------------------------------------------------
-- Drawing helpers
------------------------------------------------------------------------
local function set_col(cr, c)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
end

local _ext = nil
local function text_ext(cr, text)
    if not _ext then _ext = cairo_text_extents_t:create() end
    cairo_text_extents(cr, tostring(text), _ext)
    return _ext
end

local function setup_font(cr, font, size, bold)
    cairo_select_font_face(cr, font,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
end

local function draw_left(cr, text, x, y, font, size, col, bold)
    setup_font(cr, font, size, bold)
    set_col(cr, col)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(text))
end

local function draw_center(cr, text, cx, y, font, size, col, bold)
    setup_font(cr, font, size, bold)
    set_col(cr, col)
    local e = text_ext(cr, text)
    cairo_move_to(cr, cx - (e.width / 2 + e.x_bearing), y)
    cairo_show_text(cr, tostring(text))
end

local function draw_right(cr, text, rx, y, font, size, col, bold)
    setup_font(cr, font, size, bold)
    set_col(cr, col)
    local e = text_ext(cr, text)
    cairo_move_to(cr, rx - e.width - e.x_bearing, y)
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

local function vline(cr, x, y1, y2, col)
    set_col(cr, col)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, math.floor(x) + 0.5, y1)
    cairo_line_to(cr, math.floor(x) + 0.5, y2)
    cairo_stroke(cr)
end

local function hline(cr, x1, x2, y, col)
    set_col(cr, col)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, x1, math.floor(y) + 0.5)
    cairo_line_to(cr, x2, math.floor(y) + 0.5)
    cairo_stroke(cr)
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

local function owm_val(field, fallback)
    if not owm_get then return fallback or "--" end
    local v = owm_get(field)
    return (v ~= "N/A" and v ~= "") and v or (fallback or "--")
end

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local CFG = {
    WIDGET_W   = 260,
    WIDGET_H   = 70,
    FOOTER_H   = 14,
    OFFSET_X   = 0,
    OFFSET_Y   = 12,
    COL_TEMP_W = 95,
    COL_ICON_W = 60,
    COL_META_W = 60,
    COL_WIND_W = 60,
    PAD        = 5,
    ICON_PX    = 48,
    WIND_PNG   = "/dev/shm/conky/owm_wind.png",
    WIND_PX    = 36,
    FONT       = cairo_font or "DejaVuSansM Nerd Font Propo",
    SIZE_TEMP  = 48,
    SIZE_UNIT  = 16,
    SIZE_LABEL = 10,
    SIZE_VALUE = 16,
    SIZE_WIND  = 10,
    SIZE_FOOT  = 12,
    DRAW_BG    = false,
    BG_RADIUS  = 8,
    COLOR_BG   = { 0.05, 0.07, 0.12, 0.55 },
    COLOR_DIV  = { 1.00, 1.00, 1.00, 0.10 },
    DRAW_DIVS  = true,
}

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------
local function do_draw(cr)
    if not owm_get then
        draw_left(cr, "owm_fetch not loaded", CFG.OFFSET_X + CFG.PAD,
            CFG.OFFSET_Y + 20, CFG.FONT, 9, {1,1,1,1}, false)
        return
    end

    local temp       = owm_val("temp")
    local feels_like = owm_val("feels_like")
    local humidity   = owm_val("humidity")
    local wind_speed = owm_val("wind_speed")
    local wind_card  = owm_val("wind_card")
    local wind_unit  = owm_val("wind_unit",  "mph")
    local desc       = owm_val("desc",       "")
    local icon_metno = owm_val("icon_metno", "partlycloudy_day")
    local updated    = owm_val("updated",    "")
    local temp_unit  = owm_val("temp_unit",  "°F")

    local COL_TEMP   = { 1.00, 1.00, 1.00, 1.00 }
    local COL_UNIT   = { 0.75, 0.75, 0.75, 0.90 }
    local COL_LABEL  = { 0.70, 0.75, 0.75, 0.90 }
    local COL_WIND   = { 0.85, 0.85, 0.85, 1.00 }
    local COL_FOOTER = { 0.85, 0.85, 0.85, 1.00 }
    local COL_UPDATE = { 0.40, 0.90, 0.40, 0.80 }
    local COL_HUMID  = { 0.35, 0.75, 1.00, 1.00 }
    local COL_FEELS  = { 1.00, 0.65, 0.20, 0.90 }
    local COL_DIV    = CFG.COLOR_DIV

    local W, H, FH = CFG.WIDGET_W, CFG.WIDGET_H, CFG.FOOTER_H
    local ox, oy, P = CFG.OFFSET_X, CFG.OFFSET_Y, CFG.PAD
    local F = CFG.FONT

    if CFG.DRAW_BG then
        set_col(cr, CFG.COLOR_BG)
        rounded_rect(cr, ox, oy, W, H + FH, CFG.BG_RADIUS)
        cairo_fill(cr)
    end

    local x_temp  = ox + P
    local x_icon  = x_temp + CFG.COL_TEMP_W
    local x_meta  = x_icon + CFG.COL_ICON_W
    local x_wind  = x_meta + CFG.COL_META_W
    local cx_temp = x_temp + CFG.COL_TEMP_W / 2
    local cx_icon = x_icon + CFG.COL_ICON_W / 2
    local cx_wind = x_wind + CFG.COL_WIND_W / 2
    local mid_y   = oy + H / 2

    -- Temperature
    setup_font(cr, F, CFG.SIZE_TEMP, true)
    local te = text_ext(cr, temp)
    draw_center(cr, temp, cx_temp, mid_y + te.height / 2 - 2, F, CFG.SIZE_TEMP, COL_TEMP, true)
    draw_left(cr, temp_unit, cx_temp + te.width / 2 + 2, oy + CFG.SIZE_UNIT + 12,
        F, CFG.SIZE_UNIT, COL_UNIT, false)

    -- Icon
    draw_image(cr, fetch_metno_icon(icon_metno),
        cx_icon - CFG.ICON_PX / 2, oy + (H - CFG.ICON_PX) / 2, CFG.ICON_PX, CFG.ICON_PX)

    -- Feels like / Humidity
    local meta_x = x_meta + 6
    draw_left(cr, "Feels like",            meta_x, oy + H * 0.20, F, CFG.SIZE_LABEL, COL_LABEL, false)
    draw_left(cr, feels_like .. temp_unit, meta_x, oy + H * 0.45, F, CFG.SIZE_VALUE, COL_FEELS, true)
    draw_left(cr, "Humidity",              meta_x, oy + H * 0.65, F, CFG.SIZE_LABEL, COL_LABEL, false)
    draw_left(cr, humidity .. "%",         meta_x, oy + H * 0.88, F, CFG.SIZE_VALUE, COL_HUMID, true)

    -- Wind arrow + text
    local wf = io.open(CFG.WIND_PNG, "r")
    if wf then
        wf:close()
        draw_image(cr, CFG.WIND_PNG, cx_wind - CFG.WIND_PX / 2, oy + 4, CFG.WIND_PX, CFG.WIND_PX)
    end
    draw_center(cr, wind_card,                     cx_wind, oy + H * 0.65, F, CFG.SIZE_WIND, COL_WIND, true)
    draw_center(cr, wind_speed .. " " .. wind_unit, cx_wind, oy + H * 0.85, F, CFG.SIZE_WIND, COL_WIND, false)

    -- Column dividers
    if CFG.DRAW_DIVS then
        local dpad = H * 0.12
        vline(cr, x_icon, oy + dpad, oy + H - dpad, COL_DIV)
        vline(cr, x_meta, oy + dpad, oy + H - dpad, COL_DIV)
        vline(cr, x_wind, oy + dpad, oy + H - dpad, COL_DIV)
    end

    -- Footer
    hline(cr, ox + P, ox + W - P, oy + H + 1, COL_DIV)
    local fy = oy + H + CFG.FOOTER_H - 2
    draw_left (cr, "   " .. desc, ox + P,     fy, F, CFG.SIZE_FOOT, COL_FOOTER, false)
    draw_right(cr, updated,       ox + W - P, fy, F, CFG.SIZE_FOOT, COL_UPDATE, false)
end

------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------
function conky_weather_current()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual,  conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    local ok, err = pcall(do_draw, cr)
    if not ok then print("draw_owm_current_top error: " .. tostring(err)) end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
