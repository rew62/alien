-- kroy.lua — Kilroy Was Here + system instrumentation  (conky -c kroy.lua)
-- White on transparent. No alpha fills.
--   Left fingers  → upload speed   (3 fingers = 0–33 / 33–66 / 66–100 %)
--   Right fingers → download speed (same segmented scheme)
--   Dome          → static arc
--   Nose          → load average (droop increases with load)
--   Eyes          → CPU temperature (white cool, yellow medium, red hot)
--   Text          → hostname + uptime
--
-- Lua functions first; conky.config/text guarded by `if conky` so this file
-- is also safe to load via lua_load without re-executing the config block.

-- During config parse the `conky` global exists; cairo bindings aren't
-- registered yet so we skip the require.  lua_load re-runs this file
-- with conky=nil, at which point cairo is available.
if not conky then require 'cairo' end

local DW = 1400
local DH = 800

-- ── User config ───────────────────────────────────────────────────────────────
local function _read_env_iface()
    local home = os.getenv("HOME") or ""
    local f = io.open(home .. "/.conky/alien/.env", "r")
    if f then
        for line in f:lines() do
            local v = line:match("^INTERFACE_NAME=(.+)$")
            if v then f:close(); return v:gsub('"',''):gsub("'","") end
        end
        f:close()
    end
    return "eth0"
end
local NET_IFACE   = _read_env_iface()
local NET_MAX_KBS = 1250     -- ceiling for 100 % fill: 1250 KiB/s = 10 Mbps
local LOAD_CEIL   = 2.0      -- load average that pegs nose to max droop
--local LINE_R      = 0.33   -- line/outline color (RGB, 0.0–1.0 each)
--local LINE_G      = 0.42   -- 0,0,0 = black  |  1,1,1 = white
--local LINE_B      = 0.15   -- army green (brightened) = 0.33, 0.42, 0.15
local LINE_R      = 0.596    -- #98FB98 pale green
local LINE_G      = 0.984
local LINE_B      = 0.596
-- Text displayed below the face. Receives the data table; return any string.
-- Available fields: hostname, uptime, load, temp, up_pct, down_pct
--local TEXT = function(d) return d.hostname .. "   up " .. d.uptime end
local TEXT = function(d) return "KILLROY WAS HERE!" end

-- ─────────────────────────────────────────────────────────────────────────────

-- Evaluate a cubic bezier at parameter t (0–1)
local function bezier(t, x0, y0, x1, y1, x2, y2, x3, y3)
    local mt = 1 - t
    return mt^3*x0 + 3*mt^2*t*x1 + 3*mt*t^2*x2 + t^3*x3,
           mt^3*y0 + 3*mt^2*t*y1 + 3*mt*t^2*y2 + t^3*y3
end

-- Quadratic bezier → Cairo cubic
local function quad_to(cr, px, py, qx, qy, x2, y2)
    cairo_curve_to(cr,
        px + 2/3*(qx-px),  py + 2/3*(qy-py),
        x2 + 2/3*(qx-x2),  y2 + 2/3*(qy-y2),
        x2, y2)
end

-- Finger arch with proportional fill (fill_pct 0–100, fills from wall upward)
local function finger(cr, X, Y, xl, xr, wall, tip, fill_pct, fr, fg, fb)
    local xm     = (xl + xr) / 2
    local fill_y = Y(wall) - (fill_pct / 100) * (Y(wall) - Y(tip))

    if fill_pct > 0 then
        cairo_save(cr)
        cairo_move_to(cr, X(xl), Y(wall))
        quad_to(cr, X(xl),Y(wall),  X(xl),Y(tip),  X(xm),Y(tip))
        quad_to(cr, X(xm),Y(tip),   X(xr),Y(tip),  X(xr),Y(wall))
        cairo_close_path(cr)
        cairo_clip(cr)
        cairo_set_source_rgb(cr, fr, fg, fb)
        cairo_rectangle(cr, X(xl), fill_y, X(xr) - X(xl), Y(wall) - fill_y)
        cairo_fill(cr)
        cairo_restore(cr)
    end

    cairo_set_source_rgb(cr, LINE_R, LINE_G, LINE_B)
    cairo_move_to(cr, X(xl), Y(wall))
    quad_to(cr, X(xl),Y(wall),  X(xl),Y(tip),  X(xm),Y(tip))
    quad_to(cr, X(xm),Y(tip),   X(xr),Y(tip),  X(xr),Y(wall))
    cairo_stroke(cr)
end

-- Split a 0–100 % value into three sequential segment fills.
-- Finger 1 fills first (0–33 %), then finger 2 (33–66 %), then finger 3 (66–100 %).
local function net_fills(pct)
    local seg = 100 / 3
    local f1  = math.min(pct,         seg) / seg * 100
    local f2  = math.max(0, math.min(pct -   seg, seg)) / seg * 100
    local f3  = math.max(0, math.min(pct - 2*seg, seg)) / seg * 100
    return f1, f2, f3
end

-- ─────────────────────────────────────────────────────────────────────────────

local function kilroy(cr, w, h, data)
    local sx = w / DW
    local sy = h / DH
    local function X(x) return x * sx end
    local function Y(y) return y * sy end

    cairo_set_source_rgba(cr, 0, 0, 0, 0)
    cairo_paint(cr)

    cairo_set_source_rgb(cr, LINE_R, LINE_G, LINE_B)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    cairo_set_line_width(cr, 8 * sy)

    -- Nose droop: load 0 → Y(520), LOAD_CEIL → Y(650)
    local load_frac  = math.max(0, math.min(1, data.load / LOAD_CEIL))
    local nose_droop = 535 + load_frac * 150

    -- Eye color: 30 °C → soft white, 60 °C → muted yellow, 90 °C → muted red
    local t_frac = math.max(0, math.min(1, (data.temp - 30) / 60))
    local pr = 1
    local pg = t_frac <= 0.5 and 1 or 1 - (t_frac - 0.5) * 2
    local pb = t_frac <= 0.5 and (1 - t_frac * 2) or 0
    local eye_r = 0.25 + pr * 0.45
    local eye_g = 0.25 + pg * 0.45
    local eye_b = 0.25 + pb * 0.45

    -- ── Dome outline ──────────────────────────────────────────────────────────
    cairo_set_source_rgb(cr, LINE_R, LINE_G, LINE_B)
    cairo_move_to(cr,   X(500), Y(500))
    cairo_curve_to(cr,  X(500), Y(210), X(900), Y(210), X(900), Y(500))
    cairo_stroke(cr)

    -- ── Eyes (temperature: white cool → yellow medium → red hot) ─────────────
    cairo_set_source_rgb(cr, eye_r, eye_g, eye_b)
    cairo_arc(cr, X(630), Y(400), 14 * sx, 0, 2*math.pi)
    cairo_fill(cr)
    cairo_arc(cr, X(770), Y(400), 14 * sx, 0, 2*math.pi)
    cairo_fill(cr)
    cairo_set_source_rgb(cr, LINE_R, LINE_G, LINE_B)

    -- ── Nose ─────────────────────────────────────────────────────────────────
    cairo_move_to(cr,   X(660), Y(480))
    cairo_curve_to(cr,  X(660), Y(nose_droop),
                        X(740), Y(nose_droop), X(740), Y(480))
    cairo_stroke(cr)

    -- ── Wall ──────────────────────────────────────────────────────────────────
    cairo_move_to(cr, X(340), Y(500))
    cairo_line_to(cr, X(1060), Y(500))
    cairo_stroke(cr)

    -- ── Fingers (network, segmented) ──────────────────────────────────────────
    cairo_set_line_width(cr, 6 * sy)

    local uf1, uf2, uf3 = net_fills(data.up_pct)
    local df1, df2, df3 = net_fills(data.down_pct)

    -- left = upload  (green → yellow → red, mild)
    finger(cr, X, Y,  380, 420,  500, 460,  uf1,  0.35, 0.75, 0.35)
    finger(cr, X, Y,  420, 460,  500, 460,  uf2,  0.80, 0.75, 0.20)
    finger(cr, X, Y,  460, 500,  500, 460,  uf3,  0.75, 0.25, 0.25)

    -- right = download  (green → yellow → red, mild)
    finger(cr, X, Y,   900,  940,  500, 460,  df1,  0.35, 0.75, 0.35)
    finger(cr, X, Y,   940,  980,  500, 460,  df2,  0.80, 0.75, 0.20)
    finger(cr, X, Y,   980, 1020,  500, 460,  df3,  0.75, 0.25, 0.25)

    -- ── Text ──────────────────────────────────────────────────────────────────
    cairo_set_line_width(cr, 8 * sy)
    cairo_set_source_rgb(cr, LINE_R, LINE_G, LINE_B)
    cairo_select_font_face(cr, "Arial",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 60 * sx)

    local text = TEXT(data)
    local ext  = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, ext)
    cairo_move_to(cr,
        (w/2) - ext.width/2 - ext.x_bearing,
        Y(670))
    cairo_show_text(cr, text)
end

-- ─────────────────────────────────────────────────────────────────────────────

function conky_draw_killroy()
    if conky_window == nil then return end

    local function num(s) return tonumber(conky_parse(s)) or 0 end

    local temp = num("${hwmon 0 temp 1}")
    if temp == 0 then temp = num("${acpitemp}") end
    if temp == 0 then temp = 50 end

    local up_kbs   = num("${upspeedf "   .. NET_IFACE .. "}")
    local down_kbs = num("${downspeedf " .. NET_IFACE .. "}")

    local data = {
        up_pct   = math.min(100, up_kbs   / NET_MAX_KBS * 100),
        down_pct = math.min(100, down_kbs / NET_MAX_KBS * 100),
        load     = num("${loadavg 1}"),
        temp     = temp,
        hostname = conky_parse("${nodename}"),
        uptime   = conky_parse("${uptime}"),
    }

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height
    )
    local cr = cairo_create(cs)
    kilroy(cr, conky_window.width, conky_window.height, data)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- ─────────────────────────────────────────────────────────────────────────────

-- When loaded via lua_load, conky global is nil — skip config/text.
if conky then
    conky.config = {
        lua_load          = './kroy.lua',
        lua_draw_hook_pre = 'draw_killroy',

        background             = false,
        own_window             = true,
        own_window_type        = 'normal',
        own_window_title       = 'killroy',
        own_window_hints       = 'undecorated,below,sticky,skip_taskbar,skip_pager',
        own_window_argb_visual = true,
        own_window_argb_value  = 0,
        own_window_transparent = true,

        double_buffer          = true,
        -- Scale the widget by changing all three values proportionally.
        -- 100% = 700 x 400,  75% = 525 x 300,  50% = 350 x 200
        --minimum_width        = 700,
        --minimum_height       = 400,
        --maximum_width        = 700,
        minimum_width          = 350,
        minimum_height         = 200,
        maximum_width          = 350,
        gap_x                  = -400,
        gap_y                  = 110,

        draw_shades            = false,
        draw_borders           = false,
        draw_outline           = false,

        update_interval        = 1,
        alignment              = 'top_middle',
    }

    conky.text = [[]]
end
