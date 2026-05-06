-- aclock.lua — analog clock for Conky
-- v1.0 2026-05-05 @rew62

require 'cairo'

-- ensure settings.lua is found relative to this script's directory
local _dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. package.path
local s = require('settings')

local function hex_to_rgba(color, alpha)
    return
        math.floor(color / 0x10000)       % 0x100 / 255,
        math.floor(color / 0x100)         % 0x100 / 255,
                   color                  % 0x100 / 255,
        alpha
end

local function draw_clock(cr)
    local cx = s.cx
    local cy = s.cy
    local r  = s.radius

    local hours   = tonumber(os.date("%I"))
    local minutes = tonumber(os.date("%M"))
    local seconds = tonumber(os.date("%S"))

    local hour_len = r * s.hour_hand_pct
    local min_len  = r * s.min_hand_pct
    local sec_len  = r * s.sec_hand_pct

    -- outer ring
    cairo_set_line_width(cr, s.ring_width)
    cairo_set_source_rgba(cr, hex_to_rgba(s.ring_color, s.ring_alpha))
    cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
    cairo_stroke(cr)

    -- hour tick marks
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    for i = 0, 11 do
        local angle     = i * math.pi / 6 - math.pi / 2
        local is_major  = (i % 3 == 0)
        local tick_len  = is_major and s.tick_major_len  or s.tick_minor_len
        local tick_w    = is_major and s.tick_major_width or s.tick_minor_width
        -- start at inner edge of ring, extend inward
        local r_outer = r - s.ring_width / 2 - 2
        local r_inner = r_outer - tick_len
        cairo_set_line_width(cr, tick_w)
        cairo_set_source_rgba(cr, hex_to_rgba(s.tick_color, s.tick_alpha))
        cairo_move_to(cr, cx + r_outer * math.cos(angle), cy + r_outer * math.sin(angle))
        cairo_line_to(cr, cx + r_inner * math.cos(angle), cy + r_inner * math.sin(angle))
        cairo_stroke(cr)
    end

    -- minute tick marks + second hand (optional)
    if s.MIN_TICK then
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        local r_outer = r - s.ring_width / 2 - 2
        for i = 0, 59 do
            if i % 5 ~= 0 then   -- skip positions already covered by hour ticks
                local angle   = i * math.pi / 30 - math.pi / 2
                local r_inner = r_outer - s.min_tick_len
                cairo_set_line_width(cr, s.min_tick_width)
                cairo_set_source_rgba(cr, hex_to_rgba(s.min_tick_color, s.min_tick_alpha))
                cairo_move_to(cr, cx + r_outer * math.cos(angle), cy + r_outer * math.sin(angle))
                cairo_line_to(cr, cx + r_inner * math.cos(angle), cy + r_inner * math.sin(angle))
                cairo_stroke(cr)
            end
        end
    end

    -- hour hand
    local ha = ((hours % 12) + minutes / 60) * math.pi / 6 - math.pi / 2
    cairo_set_line_width(cr, s.hour_hand_width)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_source_rgba(cr, hex_to_rgba(s.hour_color, s.hour_alpha))
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + hour_len * math.cos(ha), cy + hour_len * math.sin(ha))
    cairo_stroke(cr)

    -- minute hand
    local ma = (minutes + seconds / 60) * math.pi / 30 - math.pi / 2
    cairo_set_line_width(cr, s.min_hand_width)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_source_rgba(cr, hex_to_rgba(s.min_color, s.min_alpha))
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + min_len * math.cos(ma), cy + min_len * math.sin(ma))
    cairo_stroke(cr)

    -- second hand (optional)
    if s.MIN_TICK then
        local sa = seconds * math.pi / 30 - math.pi / 2
        cairo_set_line_width(cr, s.sec_hand_width)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_source_rgba(cr, hex_to_rgba(s.sec_color, s.sec_alpha))
        cairo_move_to(cr, cx, cy)
        cairo_line_to(cr, cx + sec_len * math.cos(sa), cy + sec_len * math.sin(sa))
        cairo_stroke(cr)
    end

    -- center pivot
    cairo_set_source_rgba(cr, hex_to_rgba(s.center_color, s.center_alpha))
    cairo_arc(cr, cx, cy, s.center_r, 0, 2 * math.pi)
    cairo_fill(cr)

    -- alien glyph below pivot
    cairo_select_font_face(cr, s.glyph_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, s.glyph_size)
    cairo_set_source_rgba(cr, hex_to_rgba(s.glyph_color, s.glyph_alpha))
    -- offset half a glyph-width left to center; adjust glyph_offset_x in settings if needed
    cairo_move_to(cr,
        cx - s.glyph_size * 0.4,
        cy + s.center_r + s.glyph_size + 7)
    cairo_show_text(cr, s.glyph_char)
end

function conky_main()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)
    local cr = cairo_create(cs)
    draw_clock(cr)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
