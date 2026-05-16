-- complications/ram2.lua
-- Arc-style RAM usage complication for the top-left corner.
-- Arc centred at widget centre, radius 150, spanning the top-left
-- diagonal (210°–240°, 30° sweep) — mirror of the fs arc.
--
-- Arc:    0 (empty) ──── dot (used) ──── total RAM
-- Dot:    current used RAM position on arc
-- Corner: percent used, anchored to top-left corner
--
-- In CORNER_POS use: { cx = 150, cy = 150, r = 150 }
-- v1.0 2026-05-16 @rew62

local M = {}

-- Arc spans 210°–240° centred on the 225° (top-left) diagonal.
-- Cairo screen coords: 0 = right (3-o'clock), clockwise positive.
-- 210° = lower-left end  → ZERO (empty / 0)
-- 240° = upper-top  end  → FULL (total RAM)
local A_ZERO = 7 * math.pi / 6     -- 210°  zero/empty end  (lower-left)
local A_FULL = 4 * math.pi / 3     -- 240°  full/total end  (upper-top)
local SWEEP  = A_FULL - A_ZERO     -- 30° = π/6

local function read_ram()
    local pct  = tonumber(conky_parse("${memperc}")) or 0
    local size = conky_parse("${memmax}") or "?"
    size = size:match("^%s*(.-)%s*$")
    size = size:gsub("GiB", "G"):gsub("MiB", "M"):gsub("TiB", "T")
              :gsub("GB",  "G"):gsub("MB",  "M"):gsub("TB",  "T")
    return pct, size
end

function M.draw(cr, cx, cy, r)
    cairo_new_path(cr)

    local pct, size = read_ram()
    local fill_pct  = pct / 100
    local dot_a     = A_ZERO + SWEEP * fill_pct

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

    -- ── dim overlay from dot to FULL end (free / headroom) ───────────────
    if fill_pct < 0.995 then
        cairo_new_sub_path(cr)
        cairo_arc(cr, cx, cy, r, dot_a, A_FULL)
        cairo_set_line_width(cr, 5)
        cairo_set_source_rgba(cr, 0.10, 0.15, 0.35, 0.72)
        cairo_stroke(cr)
    end

    -- ── white dot at current usage ─────────────────────────────────────────
    local dot_x = cx + math.cos(dot_a) * r
    local dot_y = cy + math.sin(dot_a) * r
    cairo_new_sub_path(cr)
    cairo_arc(cr, dot_x, dot_y, 3, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_fill(cr)

    -- ── corner number: percent used, anchored top-left ────────────────────
    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 20)
    local ps = string.format("%d%%", pct)
    local pe = cairo_text_extents_t:create()
    cairo_text_extents(cr, ps, pe)
    local tx = -1
    local ty = 19 - pe.y_bearing
    cairo_set_source_rgba(cr, 1, 1, 1, 0.96)
    cairo_move_to(cr, tx, ty)
    cairo_show_text(cr, ps)

    cairo_select_font_face(cr, "DejaVu Sans",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.70)
    cairo_move_to(cr, tx, ty + 13)
    cairo_show_text(cr, "RAM")

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

    -- "0" past the zero/empty end (reverse arc direction — past the start)
    tang_label(A_ZERO,  math.sin(A_ZERO), -math.cos(A_ZERO), "0")
    -- total RAM past the full end (continuing arc direction — past the end)
    tang_label(A_FULL, -math.sin(A_FULL),  math.cos(A_FULL), size, -5, -7)
end

return M
