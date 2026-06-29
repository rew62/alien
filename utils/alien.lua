-- alien.lua — Rendered glyph logo  (conky -c alien.lua)
-- Cairo paths converted from SVG (quadratic beziers → cubic, transform applied).

if not conky then require 'cairo' end

local SVG_W = 252.34538
local SVG_H = 296.01282

local GR, GG, GB = 0.0863, 0.5098, 0.3255   -- #168253

local function draw_alien(cr, w, h)
    local function X(x) return x * w / SVG_W end
    local function Y(y) return y * h / SVG_H end

    cairo_set_source_rgba(cr, 0, 0, 0, 0)
    cairo_paint(cr)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)

    cairo_set_source_rgb(cr, GR, GG, GB)
    cairo_move_to(cr, X(13.012), Y(170.67))
    cairo_curve_to(cr, X(-6.988), Y(128), X(-3.9324), Y(87.778), X(22.179), Y(50))
    cairo_curve_to(cr, X(40.401), Y(23.556), X(68.456), Y(7.4444), X(106.35), Y(1.6667))
    cairo_curve_to(cr, X(109.23), Y(0.77778), X(112.46), Y(0.22222), X(116.01), Y(-2.3719e-06))
    cairo_line_to(cr, X(127.18), Y(-2.3719e-06))
    cairo_curve_to(cr, X(178.96), Y(1.5556), X(216.9), Y(24.556), X(241.01), Y(69))
    cairo_curve_to(cr, X(252.35), Y(90.111), X(255.18), Y(113.33), X(249.51), Y(138.67))
    cairo_curve_to(cr, X(244.96), Y(158.67), X(237.35), Y(177.44), X(226.68), Y(195))
    cairo_curve_to(cr, X(203.68), Y(230.78), X(179.96), Y(259.67), X(155.51), Y(281.67))
    cairo_curve_to(cr, X(154.18), Y(283), X(152.4), Y(284.56), X(150.18), Y(286.33))
    cairo_curve_to(cr, X(141.96), Y(292.56), X(134.35), Y(295.78), X(127.35), Y(296))
    cairo_curve_to(cr, X(120.46), Y(296.22), X(112.73), Y(293.56), X(104.18), Y(288))
    cairo_curve_to(cr, X(99.068), Y(284.89), X(94.679), Y(281.33), X(91.012), Y(277.33))
    cairo_curve_to(cr, X(56.123), Y(241.78), X(30.123), Y(206.22), X(13.012), Y(170.67))
    cairo_close_path(cr)
    cairo_move_to(cr, X(15.012), Y(131.33))
    cairo_curve_to(cr, X(15.345), Y(133.11), X(15.901), Y(135.67), X(16.679), Y(139))
    cairo_curve_to(cr, X(17.456), Y(142.33), X(18.012), Y(144.78), X(18.345), Y(146.33))
    cairo_curve_to(cr, X(23.345), Y(168.56), X(33.623), Y(185.89), X(49.179), Y(198.33))
    cairo_curve_to(cr, X(64.734), Y(210.78), X(84.068), Y(218.11), X(107.18), Y(220.33))
    cairo_curve_to(cr, X(112.29), Y(220.78), X(115.29), Y(220.56), X(116.18), Y(219.67))
    cairo_curve_to(cr, X(117.18), Y(218.78), X(117.73), Y(215.67), X(117.85), Y(210.33))
    cairo_curve_to(cr, X(117.62), Y(209), X(117.35), Y(206.72), X(117.01), Y(203.5))
    cairo_curve_to(cr, X(116.68), Y(200.28), X(116.35), Y(198), X(116.01), Y(196.67))
    cairo_curve_to(cr, X(111.57), Y(172.67), X(100.29), Y(155.22), X(82.179), Y(144.33))
    cairo_curve_to(cr, X(78.956), Y(142.33), X(75.234), Y(140.33), X(71.012), Y(138.33))
    cairo_curve_to(cr, X(66.901), Y(136.33), X(63.29), Y(134.72), X(60.179), Y(133.5))
    cairo_curve_to(cr, X(57.179), Y(132.28), X(53.123), Y(130.72), X(48.012), Y(128.83))
    cairo_curve_to(cr, X(42.901), Y(126.94), X(39.179), Y(125.44), X(36.845), Y(124.33))
    cairo_curve_to(cr, X(34.068), Y(123.22), X(29.345), Y(122.56), X(22.679), Y(122.33))
    cairo_curve_to(cr, X(16.568), Y(122.33), X(14.012), Y(125.33), X(15.012), Y(131.33))
    cairo_close_path(cr)
    cairo_move_to(cr, X(135.85), Y(209.33))
    cairo_curve_to(cr, X(135.4), Y(214.89), X(135.73), Y(218.22), X(136.85), Y(219.33))
    cairo_curve_to(cr, X(138.07), Y(220.44), X(141.35), Y(220.67), X(146.68), Y(220))
    cairo_curve_to(cr, X(153.46), Y(219.33), X(160.57), Y(218.11), X(168.01), Y(216.33))
    cairo_curve_to(cr, X(187.01), Y(211.44), X(202.57), Y(201.33), X(214.68), Y(186))
    cairo_curve_to(cr, X(220.68), Y(178.67), X(225.23), Y(170.72), X(228.35), Y(162.17))
    cairo_curve_to(cr, X(231.57), Y(153.61), X(234.4), Y(143.44), X(236.85), Y(131.67))
    cairo_curve_to(cr, X(237.73), Y(127.67), X(237.51), Y(124.89), X(236.18), Y(123.33))
    cairo_curve_to(cr, X(234.96), Y(121.78), X(232.4), Y(121.33), X(228.51), Y(122))
    cairo_curve_to(cr, X(218.07), Y(123.78), X(208.62), Y(126.11), X(200.18), Y(129))
    cairo_curve_to(cr, X(179.73), Y(136.78), X(164.18), Y(147.11), X(153.51), Y(160))
    cairo_curve_to(cr, X(142.85), Y(172.89), X(136.96), Y(189.33), X(135.85), Y(209.33))
    cairo_close_path(cr)
    cairo_fill(cr)
end

function conky_draw_alien()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    draw_alien(cr, conky_window.width, conky_window.height)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

if conky then
    conky.config = {
        lua_load          = './alien.lua',
        lua_draw_hook_pre = 'draw_alien',

        background             = false,
        own_window             = true,
        own_window_type        = 'normal',
        own_window_title       = 'alien',
        own_window_hints       = 'undecorated,below,sticky,skip_taskbar,skip_pager',
        own_window_argb_visual = true,
        own_window_argb_value  = 0,
        own_window_transparent = true,

        double_buffer  = true,
        minimum_width  = 150,
        minimum_height = 176,
        maximum_width  = 150,

        draw_shades  = false,
        draw_borders = false,
        draw_outline = false,

        update_interval = 60,
        alignment = 'top_left',
        gap_x = 100,
        gap_y = 100,
    }
    conky.text = [[]]
end
