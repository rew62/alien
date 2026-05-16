-- complications/cpu_temp.lua
--
-- Arc-style CPU temperature complication.
-- Reads k10temp Tctl on AMD systems, coretemp Package on Intel systems.
-- Fixed scale: TEMP_LO–TEMP_HI °C.
--
-- Arc:   bottom-right corner, 30°–60° sweep, same geometry as owm_weather.lua.
-- In CORNER_POS use: { cx = 150, cy = 150, r = 150 }
-- v1.0 2026-05-16 @rew62

local M = {}

local TEMP_LO = 30    -- °C  cold end of arc scale
local TEMP_HI = 95    -- °C  hot  end of arc scale

local READ_INTERVAL = 5   -- seconds between sensor reads

local _cached_temp = nil
local _last_read   = -READ_INTERVAL

local function read_cpu_temp()
    local now = os.time()
    if _cached_temp and (now - _last_read) < READ_INTERVAL then
        return _cached_temp
    end
    local t = nil
    -- AMD: k10temp Tctl
    local f = io.popen("sensors k10temp-pci-* 2>/dev/null | grep -m1 Tctl | grep -oE '[0-9]+\\.[0-9]+'")
    if f then
        local s = f:read("*l"); f:close()
        t = tonumber(s)
    end
    -- Intel: coretemp Package id 0
    if not t then
        f = io.popen("sensors coretemp-isa-* 2>/dev/null | grep -m1 'Package id' | grep -oE '[0-9]+\\.[0-9]+'")
        if f then
            local s = f:read("*l"); f:close()
            t = tonumber(s)
        end
    end
    if t then
        _cached_temp = math.floor(t + 0.5)
        _last_read   = now
    end
    return _cached_temp
end

-- Arc geometry: bottom-right corner, 30°–60° sweep (same as owm_weather.lua)
-- Cairo screen coords: 0 = right (3-o'clock), clockwise positive.
-- 30° = upper end  → HOT  (TEMP_HI)
-- 60° = lower end  → COLD (TEMP_LO)
local A_HI  = math.pi / 6   -- 30°  hot end
local A_LO  = math.pi / 3   -- 60°  cold end
local SWEEP = A_LO - A_HI   -- 30° = π/6

local function lerp(a, b, t) return a + (b - a) * t end

local function temp_color(pct)
    if pct < 0.5 then
        local t = pct / 0.5
        return lerp(0.30, 0.92, t), lerp(0.72, 0.76, t), lerp(1.00, 0.22, t)
    else
        local t = (pct - 0.5) / 0.5
        return lerp(0.92, 1.00, t), lerp(0.76, 0.18, t), lerp(0.22, 0.05, t)
    end
end

function M.draw(cr, cx, cy, r)
    cairo_new_path(cr)

    local temp = read_cpu_temp()
    if not temp then return end

    local pct   = math.max(0, math.min(1, (temp - TEMP_LO) / (TEMP_HI - TEMP_LO)))
    local dot_a = A_LO - SWEEP * pct
    local vr, vg, vb = temp_color(pct)

    -- ── full arc background (faint) ───────────────────────────────────────
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

    -- ── dim overlay: unfilled hot portion (A_HI → dot) ───────────────────
    if pct < 0.995 then
        cairo_new_sub_path(cr)
        cairo_arc(cr, cx, cy, r, A_HI, dot_a)
        cairo_set_line_width(cr, 5)
        cairo_set_source_rgba(cr, 0.10, 0.15, 0.35, 0.72)
        cairo_stroke(cr)
    end

    -- ── coloured dot at current temp ──────────────────────────────────────
    local dot_x = cx + math.cos(dot_a) * r
    local dot_y = cy + math.sin(dot_a) * r
    cairo_new_sub_path(cr)
    cairo_arc(cr, dot_x, dot_y, 3, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, vr, vg, vb, 1)
    cairo_fill(cr)

    -- ── current temp — anchored to bottom-right corner ────────────────────
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 20)
    local ts = string.format("%d\xc2\xb0", temp)
    local te = cairo_text_extents_t:create()
    cairo_text_extents(cr, ts, te)
    local tx = (cx * 2) - 4 - (te.width  + te.x_bearing)
    local ty = (cy * 2) - 19 - (te.height + te.y_bearing)
    cairo_set_source_rgba(cr, vr, vg, vb, 0.96)
    cairo_move_to(cr, tx, ty)
    cairo_show_text(cr, ts)

    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)
    local tl = cairo_text_extents_t:create()
    cairo_text_extents(cr, "CPU", tl)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.70)
    cairo_move_to(cr, (cx * 2) - 6 - (tl.width + tl.x_bearing), ty + 13)
    cairo_show_text(cr, "CPU")

    -- ── lo / hi scale labels at arc endpoints ─────────────────────────────
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

    -- cold end (A_LO): TEMP_LO label
    tang_label(A_LO, -math.sin(A_LO),  math.cos(A_LO), tostring(TEMP_LO))
    -- hot  end (A_HI): TEMP_HI label
    tang_label(A_HI,  math.sin(A_HI), -math.cos(A_HI), tostring(TEMP_HI))
end

return M
