-- complications/cpu_load2.lua
-- Arc-style CPU usage complication for the top-right corner.
-- Arc centred at widget centre, radius 150, spanning the top-right
-- diagonal (300°–330°, 30° sweep) — mirror of the ram2 arc.
--
-- Arc:    0 (empty) ──── dot (used) ──── 100%
-- Dot:    current CPU position on arc
-- Corner: percent used, anchored to top-right corner
--
-- In CORNER_POS use: { cx = 150, cy = 150, r = 150 }
-- v1.0 2026-05-16 @rew62

local M = {}

-- Arc spans 300°–330° centred on the 315° (top-right) diagonal.
-- Cairo screen coords: 0 = right (3-o'clock), clockwise positive.
-- 300° = upper end  → ZERO (empty / 0)
-- 330° = right  end → FULL (100%)
local A_ZERO = 5 * math.pi / 3     -- 300°  zero/empty end  (upper)
local A_FULL = 11 * math.pi / 6    -- 330°  full/max   end  (right)
local SWEEP  = A_FULL - A_ZERO     -- 30° = π/6

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function arc_color(pct)
    if pct < 0.55 then
        local t = pct / 0.55
        return lerp(0.30, 0.92, t), lerp(0.72, 0.76, t), lerp(1.00, 0.22, t)
    else
        local t = (pct - 0.55) / 0.45
        return lerp(0.92, 1.00, t), lerp(0.76, 0.18, t), lerp(0.22, 0.05, t)
    end
end

function M.draw(cr, cx, cy, r)
    cairo_new_path(cr)

    local cpu     = math.min(tonumber(conky_parse("${cpu cpu0}")) or 0, 100)
    local fill_pct = cpu / 100
    local dot_a   = A_FULL - SWEEP * fill_pct

    local vr, vg, vb = arc_color(fill_pct)

    -- ── full arc background (bright, full span) ───────────────────────────
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, A_ZERO, A_FULL)
    cairo_set_line_width(cr, 10)
    cairo_set_source_rgba(cr, 0.55, 0.78, 1.0, 0.14)
    cairo_stroke(cr)

    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, A_ZERO, A_FULL)
    cairo_set_line_width(cr, 5)
    cairo_set_source_rgba(cr, 0.70, 0.87, 1.0, 0.96)
    cairo_stroke(cr)

    -- ── dim overlay from ZERO end to dot (unused headroom) ───────────────
    if fill_pct < 0.995 then
        cairo_new_sub_path(cr)
        cairo_arc(cr, cx, cy, r, A_ZERO, dot_a)
        cairo_set_line_width(cr, 5)
        cairo_set_source_rgba(cr, 0.10, 0.15, 0.35, 0.72)
        cairo_stroke(cr)
    end

    -- ── coloured dot at current usage ─────────────────────────────────────
    local dot_x = cx + math.cos(dot_a) * r
    local dot_y = cy + math.sin(dot_a) * r
    cairo_new_sub_path(cr)
    cairo_arc(cr, dot_x, dot_y, 3, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, vr, vg, vb, 1)
    cairo_fill(cr)

    -- ── corner number: percent used, anchored top-right ──────────────────
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 20)
    local ps = string.format("%d%%", cpu)
    local pe = cairo_text_extents_t:create()
    cairo_text_extents(cr, ps, pe)
    local tx = (cx * 2) - 4 - (pe.width + pe.x_bearing)
    local ty = 19 - pe.y_bearing
    cairo_set_source_rgba(cr, 1, 1, 1, 0.96)
    cairo_move_to(cr, tx, ty)
    cairo_show_text(cr, ps)

    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)
    local cl = cairo_text_extents_t:create()
    cairo_text_extents(cr, "CPU", cl)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.70)
    cairo_move_to(cr, (cx * 2) - 6 - (cl.width + cl.x_bearing), ty + 13)
    cairo_show_text(cr, "CPU")

    -- ── endpoint labels, tangentially extended past each arc end ─────────
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)

    local GAP = 14

    local function tang_label(angle, tan_dx, tan_dy, str, dy, dx)
        local e = cairo_text_extents_t:create()
        cairo_text_extents(cr, str, e)
        local ex = cx + math.cos(angle) * r + tan_dx * GAP + (dx or 0)
        local ey = cy + math.sin(angle) * r + tan_dy * GAP + (dy or 0)
        cairo_set_source_rgba(cr, 0.65, 0.80, 1, 0.82)
        cairo_move_to(cr,
            ex - (e.width  / 2 + e.x_bearing),
            ey - (e.height / 2 + e.y_bearing))
        cairo_show_text(cr, str)
    end

    -- "100" past the zero end (upper/top — now the full end)
    tang_label(A_ZERO,  math.sin(A_ZERO), -math.cos(A_ZERO), "100", -4, 10)
    -- "0" past the full end (right/base — now the zero end)
    tang_label(A_FULL, -math.sin(A_FULL),  math.cos(A_FULL), "0", nil, -3)
end

return M
