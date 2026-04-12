-- clock.lua - Animated clock widget for Conky - Every second the colon swaps color.
-- Font: Metropolis (https://github.com/chrismsimpson/Metropolis/releases)
-- v1.1 2026-04-09 @rew62
--

require 'cairo'

-- ── helpers ──────────────────────────────────────────────────────────────────

local function set_color(cr, hex, alpha)
    local r = tonumber(hex:sub(1,2), 16) / 255
    local g = tonumber(hex:sub(3,4), 16) / 255
    local b = tonumber(hex:sub(5,6), 16) / 255
    cairo_set_source_rgba(cr, r, g, b, alpha or 1.0)
end

local function draw_text(cr, text, font, size, bold, x, y, hex, alpha)
    cairo_select_font_face(cr, font,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    set_color(cr, hex, alpha or 1.0)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, text)
end

local function get_text_width(cr, text, font, size, bold)
    cairo_select_font_face(cr, font,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    tolua.takeownership(ext)
    cairo_text_extents(cr, text, ext)
    return ext.width
end

local function get_text_extents_full(cr, text, font, size, bold)
    cairo_select_font_face(cr, font,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    tolua.takeownership(ext)
    cairo_text_extents(cr, text, ext)
    return ext
end

-- ── main draw hook ────────────────────────────────────────────────────────────

function conky_draw_clock()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)

    local cr = cairo_create(cs)

    -- ── time values ──────────────────────────────────────────────────────────
    local hours   = tonumber(os.date('%I'))
    local minutes = os.date('%M')
    local seconds = tonumber(os.date('%S'))
    local ampm    = os.date('%p')
    local month   = os.date('%B'):upper()
    local day     = tostring(tonumber(os.date('%d')))
    local weekday = os.date('%A')
    local h_str   = string.format('%02d', hours)

    -- ── constants ─────────────────────────────────────────────────────────────
    local FONT      = 'Metropolis'
    local TIME_SIZE = 78
    local DOT_R     = 7
    local BASE_Y    = 80

    --local COLOR_TIME = 'E8907A'   -- coral / salmon
    local COLOR_TIME = '00F5FF'
    local COLOR_COOL = 'C8BEB9'   -- muted off-white for the "cool" dot
    local COLOR_DIV  = 'D4CECA'
    local COLOR_AMPM = 'D4CECA'

    local MONTH_COLORS = {
        ['01']='E57373', ['02']='F06292', ['03']='BA68C8', ['04']='9575CD',
        ['05']='7986CB', ['06']='64B5F6', ['07']='4DD0E1', ['08']='4DB6AC',
        ['09']='81C784', ['10']='AED581', ['11']='FFB74D', ['12']='A1887F',
    }
    local COLOR_MONTH = MONTH_COLORS[os.date('%m')] or COLOR_DIV

    -- Odd seconds  → top dot is hot (coral), bottom dot is cool (white)
    -- Even seconds → bottom dot is hot,      top dot is cool
    local top_hot = (seconds % 2 == 1)

    -- ── x positions ──────────────────────────────────────────────────────────
    local w_h       = get_text_width(cr, h_str,   FONT, TIME_SIZE, false)
    local w_m       = get_text_width(cr, minutes, FONT, TIME_SIZE, false)
    local colon_gap = 30
    local x_h       = 14 
    local x_col     = x_h + w_h + 6
    local x_m       = x_col + colon_gap
    local x_post    = x_m + w_m + 12

    -- ── hours ─────────────────────────────────────────────────────────────────
    draw_text(cr, h_str, FONT, TIME_SIZE, false, x_h, BASE_Y, COLOR_TIME, 0.88)

    -- ── colon dots (both always visible, swap color each second) ─────────────
    local dot_x   = x_col + colon_gap / 2
    local mid_y   = BASE_Y - TIME_SIZE * 0.38
    local dot_sep = 20

    -- Top dot
    cairo_arc(cr, dot_x, mid_y - dot_sep * 0.5, DOT_R, 0, 2 * math.pi)
    if top_hot then
        set_color(cr, COLOR_TIME, 0.92)
    else
        set_color(cr, COLOR_COOL, 0.55)
    end
    cairo_fill(cr)

    -- Bottom dot
    cairo_arc(cr, dot_x, mid_y + dot_sep * 0.5, DOT_R, 0, 2 * math.pi)
    if top_hot then
        set_color(cr, COLOR_COOL, 0.55)
    else
        set_color(cr, COLOR_TIME, 0.92)
    end
    cairo_fill(cr)

    -- ── minutes ───────────────────────────────────────────────────────────────
    draw_text(cr, minutes, FONT, TIME_SIZE, false, x_m, BASE_Y, COLOR_TIME, 0.88)

    -- ── AM/PM ────────────────────────────────────────────────────────────────
    draw_text(cr, ampm, FONT, 15, true,
              x_post, BASE_Y - TIME_SIZE * 0.60 + 5, COLOR_AMPM, 0.80)

    -- ── vertical divider ─────────────────────────────────────────────────────
    local div_x = x_post + 35
    cairo_set_line_width(cr, 1.2)
    set_color(cr, COLOR_DIV, 0.28)
    cairo_move_to(cr, div_x, BASE_Y - TIME_SIZE * 0.88 + 10)
    cairo_line_to(cr, div_x, BASE_Y + 16)
    cairo_stroke(cr)

    -- ── date block (centered vertically in divider, centered horizontally) ──
    local date_x  = div_x + 14
    local date_cx = (date_x + conky_window.width) / 2 - 5  -- horizontal center of date column

    local ext_mo  = get_text_extents_full(cr, month,   FONT, 18, true)
    local ext_dy  = get_text_extents_full(cr, day,     FONT, 34, false)
    local ext_wd  = get_text_extents_full(cr, weekday, FONT, 16, false)

    local gap     = 10
    local total_h = ext_mo.height + gap + ext_dy.height + gap + ext_wd.height

    local div_y1    = BASE_Y - TIME_SIZE * 0.88 + 10
    local div_y2    = BASE_Y + 16
    local block_top = (div_y1 + div_y2) / 2 - total_h / 2

    -- baseline = top_of_ink_block - y_bearing  (y_bearing is negative)
    local mo_y  = block_top - ext_mo.y_bearing
    local dy_y  = mo_y  + ext_mo.y_bearing + ext_mo.height + gap - ext_dy.y_bearing
    local wd_y  = dy_y  + ext_dy.y_bearing + ext_dy.height + gap - ext_wd.y_bearing

    -- center each label horizontally: x = center - x_bearing - width/2
    local mo_x  = date_cx - ext_mo.x_bearing - ext_mo.width  / 2
    local dy_x  = date_cx - ext_dy.x_bearing - ext_dy.width  / 2
    local wd_x  = date_cx - ext_wd.x_bearing - ext_wd.width  / 2

    draw_text(cr, month,   FONT, 18, true,  mo_x, mo_y, COLOR_MONTH, 0.90)
    draw_text(cr, day,     FONT, 34, false, dy_x, dy_y, 'FFFFFF',    0.90)
    draw_text(cr, weekday, FONT, 16, false, wd_x, wd_y, 'B8B4B2',    0.70)

    -- ── cleanup ───────────────────────────────────────────────────────────────
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
