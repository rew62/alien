-- draw_owm_current_sidepanel.lua - OWM current conditions, sidepanel layout
-- Visual port of wttr/owm_current_sidepanel.rc; drawn entirely by Lua/Cairo.
-- Data via owm_get() from scripts/owm_fetch.lua
-- v1.0 2026-05-21 @rew62
--
--  ┌───────────────────────────────────────────────────────┐
--  │ [icon]    68°F    │  LOCATION                        │
--  │                   │  CITY NAME                       │
--  │                   │  WEATHER                         │
--  │                   │  SCATTERED CLOUDS                │
--  ├───────────────────────────────────────────────────────┤
--  │  FEELS LIKE   │  HUMIDITY     │  WIND SPEED          │
--  │  65°F         │  62%          │  NW 12 mph           │
--  └───────────────────────────────────────────────────────┘

require 'cairo'

------------------------------------------------------------------------
-- Metno icon helper
------------------------------------------------------------------------
local METNO_CACHE = "/dev/shm/conky_icons/"
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

local function owm_val(field, fallback)
    if not owm_get then return fallback or "--" end
    local v = owm_get(field)
    return (v ~= "N/A" and v ~= "") and v or (fallback or "--")
end

------------------------------------------------------------------------
-- Config  ← x positions match wttr goto values exactly
------------------------------------------------------------------------
local ICON_MODE   = "emoji"   -- "metno" | "emoji"
local FONT_EMOJI  = "DejaVuSansM Nerd Font Propo"

local CFG = {
    W       = 315,
    H       = 100,
    SPLIT_Y = 68,
    ICON_X  = 28,       -- centers 48px icon around wttr's goto 37
    TEMP_X  = 120,
    COL2_X  = 205,
    STAT_XS = { 40, 140, 225 },
    ICON_PX = 48,
    FONT_TEMP  = "Bebas Neue",
    FONT_LABEL = "Rubik",
    FONT_VAL   = "Rubik",
    SIZE_TEMP  = 48,    -- wttr Bebas Neue:size=33
    SIZE_UNIT  = 18,
    SIZE_LABEL = 9,
    SIZE_VAL   = 10,
    OFFSET_Y   = 15,    -- shift entire widget down in window
}

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------
local function do_draw(cr)
    if not owm_get then
        draw_left(cr, "owm_fetch not loaded", 8, 20, CFG.FONT_VAL, 9, {1,1,1,1}, false)
        return
    end

    local temp       = owm_val("temp")
    local feels_like = owm_val("feels_like")
    local humidity   = owm_val("humidity")
    local wind_speed = owm_val("wind_speed")
    local wind_card  = owm_val("wind_card")
    local wind_unit  = owm_val("wind_unit",  "mph")
    local desc       = string.upper(owm_val("desc", "")):sub(1, 16)
    local icon_metno = owm_val("icon_metno", "partlycloudy_day")
    local location   = string.upper(owm_val("location", ""))
    local temp_unit  = owm_val("temp_unit",  "°F")

    local C_WHITE  = { 1.00, 1.00, 1.00, 1.00 }
    local C_DIM    = { 0.75, 0.75, 0.75, 0.90 }
    local C_PURPLE = { 0.45, 0.26, 0.92, 1.00 }  -- color1 = 7342EB
    local C_BLUE   = { 0.18, 0.62, 0.92, 1.00 }  -- color2 = 2D9EEA
    local C_DIV    = { 1.00, 1.00, 1.00, 0.12 }
    local C_MUTED  = { 0.60, 0.60, 0.60, 0.85 }

    local SY = CFG.SPLIT_Y
    local OY = CFG.OFFSET_Y

    -- Icon
    if ICON_MODE == "emoji" then
        local icon_emoji = owm_val("icon_emoji", "?"):gsub("\xef\xb8\x8f", "")  -- strip U+FE0F color selector
        local ey = OY + (SY + CFG.ICON_PX) / 2 - 14
        draw_left(cr, icon_emoji, CFG.ICON_X, ey, FONT_EMOJI, 96, C_WHITE, false)
    else
        draw_image(cr, fetch_metno_icon(icon_metno),
            CFG.ICON_X, OY + (SY - CFG.ICON_PX) / 2, CFG.ICON_PX, CFG.ICON_PX)
    end

    -- Temperature (Bebas Neue)
    setup_font(cr, CFG.FONT_TEMP, CFG.SIZE_TEMP, false)
    local te = text_ext(cr, temp)
    local temp_y = OY + SY * 0.60 + 10
    draw_left(cr, temp,      CFG.TEMP_X,                temp_y, CFG.FONT_TEMP, CFG.SIZE_TEMP, C_WHITE, false)
    draw_left(cr, temp_unit, CFG.TEMP_X + te.width + 6,
        temp_y - te.height * 0.50 - 2,                         CFG.FONT_VAL,  CFG.SIZE_UNIT, C_DIM,   false)

    -- LOCATION / WEATHER (Rubik, right column)
    local lx = CFG.COL2_X
    draw_left(cr, "LOCATION", lx, OY + 14, CFG.FONT_LABEL, CFG.SIZE_LABEL, C_PURPLE, true)
    draw_left(cr, location,   lx, OY + 25, CFG.FONT_VAL,   CFG.SIZE_VAL,   C_WHITE,  true)
    draw_left(cr, "WEATHER",  lx, OY + 47, CFG.FONT_LABEL, CFG.SIZE_LABEL, C_PURPLE, true)
    draw_left(cr, desc,       lx, OY + 58, CFG.FONT_VAL,   CFG.SIZE_VAL,   C_WHITE,  false)

    -- Stats row (Rubik, wttr goto positions)
    local label_y = OY + SY + 17
    local value_y = OY + SY + 29
    local stats = {
        { lbl = "FEELS LIKE", val = feels_like .. temp_unit },
        { lbl = "HUMIDITY",   val = humidity   .. "%" },
        { lbl = "WIND SPEED", val = wind_card  .. " " .. wind_speed .. " " .. wind_unit },
    }
    for i, s in ipairs(stats) do
        local sx = CFG.STAT_XS[i]
        draw_left(cr, s.lbl, sx, label_y, CFG.FONT_LABEL, CFG.SIZE_LABEL, C_BLUE,  true)
        draw_left(cr, s.val, sx, value_y, CFG.FONT_VAL,   CFG.SIZE_VAL,   C_WHITE, true)
    end

    -- Cache freshness timestamp (mtime of owm_current.json)
    local ts_str = ""
    local fh = io.popen("stat -c %Y /dev/shm/conky/owm_current.json 2>/dev/null")
    if fh then
        local epoch = tonumber(fh:read("*l"))
        fh:close()
        if epoch then
            ts_str = os.date("%I:%M%p", epoch):gsub("^0", ""):lower():gsub("m$", "")
        end
    end
    if ts_str ~= "" then
        local tx = CFG.W - 4
        draw_left(cr, ts_str, tx - 25, value_y + 6, CFG.FONT_VAL, CFG.SIZE_VAL, C_MUTED, false)
    end
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
    if not ok then print("draw_owm_current_sidepanel error: " .. tostring(err)) end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
