-- vnstat-sum2.lua  Cairo-rendered vnstat day / week / month summary
-- v1.0 2026-06-16 @rew62

package.path = package.path .. ";./?.lua;../?.lua;"
            .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

local cjson
do
    local ok, lib = pcall(require, "cjson")
    if ok then cjson = lib
    else
        local ok2, lib2 = pcall(require, "json")
        if ok2 then cjson = lib2
        else print("FATAL: no JSON library found") end
    end
end

-- ── layout ──────────────────────────────────────────────────────────────────
local M   = 8        -- left / right margin
local W   = 307      -- widget width (matches minimum_width in rc)
local XR  = W - M   -- right content edge  (299)
local XUP = 190      -- Upload column right edge

-- ── colors ──────────────────────────────────────────────────────────────────
local function mk(h)
    return { math.floor(h / 0x10000) / 255,
             math.floor(h / 0x100) % 256 / 255,
             h % 256 / 255 }
end
local COL = {
    header = mk(0x89b4fa),   -- section header blue
    lbl    = mk(0x2D9EEA),   -- row label blue (from net.rc)
    rx     = mk(0x60c888),   -- download green
    tx     = mk(0xf05555),   -- upload red
    white  = mk(0xe8e8e8),   -- values / iface name
    sep    = mk(0xa06828),   -- separator lines
    dim    = mk(0x8a6030),   -- dimmed / error text
}

-- ── Cairo helpers ────────────────────────────────────────────────────────────
local function set_col(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1.0)
end

local function x_advance(cr, s)
    local e = cairo_text_extents_t:create()
    tolua.takeownership(e)
    cairo_text_extents(cr, s, e)
    return e.x_advance
end

local function dl(cr, x, y, s)      -- draw left-aligned
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, s)
end

local function dr(cr, x, y, s)      -- draw right-aligned
    cairo_move_to(cr, x - x_advance(cr, s), y)
    cairo_show_text(cr, s)
end

local function sep_line(cr, y)
    cairo_move_to(cr, M, y)
    cairo_line_to(cr, XR, y)
    cairo_stroke(cr)
end

-- ── data helpers ─────────────────────────────────────────────────────────────
local function fmt_bytes(b)
    b = tonumber(b) or 0
    local K = 1024
    if     b >= K^4 then return string.format("%.2f TB", b / K^4)
    elseif b >= K^3 then return string.format("%.2f GB", b / K^3)
    elseif b >= K^2 then return string.format("%.2f MB", b / K^2)
    elseif b >= K   then return string.format("%.2f KB", b / K)
    else                 return string.format("%.0f B",  b)
    end
end

local function get_vnstat(iface)
    local p = io.popen("vnstat -i " .. iface .. " --json 2>/dev/null")
    if not p then return nil end
    local raw = p:read("*a"); p:close()
    if not raw or raw == "" then return nil end
    local ok, data = pcall(cjson.decode, raw)
    return ok and data or nil
end

local function date_num(d)
    return d.year * 10000 + d.month * 100 + d.day
end

local function week_range()
    local today = os.date("*t")
    local start_wday = (var_WEEK_START == "monday") and 2 or 1
    local days_back  = (today.wday - start_wday + 7) % 7
    local wstart     = os.date("*t", os.time(today) - days_back * 86400)
    return today, wstart
end

-- ── main draw ────────────────────────────────────────────────────────────────
function conky_draw_vnstat_sum2()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual,  conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    local iface_name = var_NETWORK or "wlp2s0"

    -- ── title row ─────────────────────────────────────────────────────────
    local Y1 = 18
    cairo_select_font_face(cr, "Rubik", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 12)
    set_col(cr, COL.header)
    dl(cr, M, Y1, "vnstat")
    set_col(cr, COL.white)
    dr(cr, XR, Y1, iface_name)

    -- ── fetch & locate interface ──────────────────────────────────────────
    local data  = get_vnstat(iface_name)
    local iface = nil
    if data and data.interfaces then
        for _, v in ipairs(data.interfaces) do
            if v.name == iface_name then iface = v; break end
        end
    end

    if not iface then
        cairo_select_font_face(cr, "Rubik", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 11)
        set_col(cr, COL.dim)
        dl(cr, M, 40, "no data — is vnstatd running?")
        cairo_destroy(cr); cairo_surface_destroy(cs); return
    end

    -- ── accumulate period totals ──────────────────────────────────────────
    local today, wstart = week_range()
    local today_n  = date_num(today)
    local wstart_n = date_num(wstart)

    local day_rx, day_tx = 0, 0
    for _, d in ipairs(iface.traffic.day or {}) do
        if date_num(d.date) == today_n then
            day_rx = d.rx or 0; day_tx = d.tx or 0; break
        end
    end

    local week_rx, week_tx = 0, 0
    for _, d in ipairs(iface.traffic.day or {}) do
        local n = date_num(d.date)
        if n >= wstart_n and n <= today_n then
            week_rx = week_rx + (d.rx or 0)
            week_tx = week_tx + (d.tx or 0)
        end
    end

    local mon_rx, mon_tx = 0, 0
    for _, m in ipairs(iface.traffic.month or {}) do
        if m.date.year == today.year and m.date.month == today.month then
            mon_rx = m.rx or 0; mon_tx = m.tx or 0; break
        end
    end

    -- ── column headers ────────────────────────────────────────────────────
    local Y2 = 40
    cairo_select_font_face(cr, "Rubik", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 10)
    set_col(cr, COL.tx)
    dr(cr, XUP, Y2, "Upload")
    set_col(cr, COL.rx)
    dr(cr, XR,  Y2, "Download")

    -- ── separator 1 ───────────────────────────────────────────────────────
    cairo_set_line_width(cr, 0.5)
    set_col(cr, COL.sep)
    sep_line(cr, 48)

    -- ── data rows ─────────────────────────────────────────────────────────
    cairo_select_font_face(cr, "Rubik", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 12)
    local rows = {
        { "today", day_rx,  day_tx  },
        { "week",  week_rx, week_tx },
        { "month", mon_rx,  mon_tx  },
    }
    local y = 66
    for _, row in ipairs(rows) do
        local lbl, rx, tx = row[1], row[2], row[3]
        set_col(cr, COL.lbl);  dl(cr, M,   y, lbl)
        set_col(cr, COL.tx);   dr(cr, XUP, y, fmt_bytes(tx))
        set_col(cr, COL.rx);   dr(cr, XR,  y, fmt_bytes(rx))
        y = y + 20
    end

    -- ── separator 2 ───────────────────────────────────────────────────────
    local Y_S2 = y + 2
    set_col(cr, COL.sep)
    sep_line(cr, Y_S2)

    -- ── footer: two-color right-aligned "updated: <time>" ─────────────────
    cairo_select_font_face(cr, "Rubik", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 10)
    local Y_F  = Y_S2 + 16
    local ts   = os.date("%I:%M %p"):lower()
    local ts_w = x_advance(cr, ts)
    set_col(cr, COL.white)
    cairo_move_to(cr, XR - ts_w, Y_F)
    cairo_show_text(cr, ts)
    local lbl   = "updated: "
    local lbl_w = x_advance(cr, lbl)
    set_col(cr, COL.header)
    cairo_move_to(cr, XR - ts_w - lbl_w, Y_F)
    cairo_show_text(cr, lbl)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
