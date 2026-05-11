-- vnstat.lua - vnstat network statistics conky widget
-- v1.1 2026-05-11 @rew62

-- -----------------------------------------------------------------------
-- JSON DEPENDENCY FALLBACK
-- -----------------------------------------------------------------------
-- package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua"
package.path = package.path .. ";./?.lua;../?.lua;" .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

local cjson = nil

local ok, lib = pcall(require, "cjson")
  if ok then
    cjson = lib
  else
    local ok2, lib2 = pcall(require, "json")
    if ok2 then
        cjson = lib2
        print("cjson not found, using scripts/json.lua fallback.")
    else
        print("FATAL: no JSON library found")
    end
end

local IFACE      = "wlp2s0"    -- default; overridden by var_NETWORK from settings.lua
local MAX_HOURS  = 10          -- how many hourly rows to show
local MAX_DAYS   = 21          -- how many daily rows to show

-- ── colour helpers (conky inline colour tags) ───────────────────────
local C = {
    tree    = "${color5}",
    header  = "${color6}",
    label   = "${color}",
    val     = "${color1}",
    dim     = "${color4}",
    rx      = "${color2}",
    tx      = "${color3}",
    white   = "${color e8e8e8}",
    reset   = "${color}",
}

-- ── unit formatting ─────────────────────────────────────────────────
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

local function pad(s, w)
    s = tostring(s)
    return string.rep(" ", math.max(0, w - #s)) .. s
end

-- ── run vnstat and parse JSON ────────────────────────────────────────
local function get_vnstat()
    local cmd  = "vnstat -i " .. IFACE .. " --json 2>/dev/null"
    local pipe = io.popen(cmd)
    if not pipe then return nil end
    local raw  = pipe:read("*a")
    pipe:close()
    if not raw or raw == "" then return nil end
    local ok, data = pcall(cjson.decode, raw)
    if not ok then return nil end
    return data
end

-- ── build hourly block ───────────────────────────────────────────────
local function hourly_block(iface)
    local hours = iface.traffic and iface.traffic.hour
    if not hours or #hours == 0 then
        return C.tree .. "├── " .. C.dim .. "(no hourly data)\n"
    end

    -- sort descending by timestamp so most-recent first
    table.sort(hours, function(a, b)
        local ta = (a.date and a.date.year or 0)*1000000
                 + (a.date and a.date.month or 0)*10000
                 + (a.date and a.date.day   or 0)*100
                 + (a.time and a.time.hour  or 0)
        local tb = (b.date and b.date.year or 0)*1000000
                 + (b.date and b.date.month or 0)*10000
                 + (b.date and b.date.day   or 0)*100
                 + (b.time and b.time.hour  or 0)
        return ta > tb
    end)

    local shown  = math.min(MAX_HOURS, #hours)
    local total_rx, total_tx = 0, 0
    local max_tot, min_tot   = 0, math.huge
    local max_label, min_label = "", ""

    for i = 1, shown do
        local h  = hours[i]
        local rx = h.rx or 0
        local tx = h.tx or 0
        local tot = rx + tx
        total_rx = total_rx + rx
        total_tx = total_tx + tx
        if tot > max_tot then
            max_tot   = tot
            max_label = string.format("[%02d:00 - %02d:00]",
                h.time.hour, (h.time.hour + 1) % 24)
        end
        if tot < min_tot then
            min_tot   = tot
            min_label = string.format("[%02d:00 - %02d:00]",
                h.time.hour, (h.time.hour + 1) % 24)
        end
    end

    local grand = total_rx + total_tx
    local avg   = (shown > 0) and (grand / shown) or 0

    local out = ""
    out = out .. C.tree .. "├─ " .. C.header .. "hourly : "
               .. C.white .. shown .. " entries\n"
    out = out .. C.tree .. "│\n"

    -- detect whether hours span more than one calendar day
    local multi_day = false
    if shown > 1 then
        local first = hours[1]
        for i = 2, shown do
            local h = hours[i]
            if h.date.day ~= first.date.day or h.date.month ~= first.date.month then
                multi_day = true; break
            end
        end
    end

    -- column layout: label=11, value cols=10 each
    local LW, VW = 11, 10
    -- column header aligned to value columns
    out = out .. C.tree .. "│" .. string.rep(" ", 3 + LW)
              .. C.tx    .. pad("Upload",   VW)
              .. "  "
              .. C.rx    .. pad("Download", VW)
              .. "  "
              .. C.val   .. pad("Total",    VW) .. "\n"
    out = out .. C.tree .. "│\n"

    -- per-hour rows
    for i = 1, shown do
        local h   = hours[i]
        local rx  = h.rx or 0
        local tx  = h.tx or 0
        local tot = rx + tx
        local prefix = "├──"
        local hr_label
        if multi_day then
            hr_label = string.format("%02d-%02d %02d:00",
                h.date.month, h.date.day, h.time.hour)
        else
            hr_label = string.format("Hr: %02d:00  ", h.time.hour)
        end
        out = out .. C.tree .. prefix .. " "
                  .. C.val  .. hr_label
                  .. C.tx   .. pad(fmt_bytes(tx),  VW)
                  .. "  "
                  .. C.rx   .. pad(fmt_bytes(rx),  VW)
                  .. "  "
                  .. C.white .. pad(fmt_bytes(tot), VW)
                  .. "\n"
    end

    out = out .. "${font Monospace:bold:size=9}"
              .. C.tree .. "└── " .. C.header .. string.format("%-11s", "total")
              .. C.tx   .. pad(fmt_bytes(total_tx), VW)
              .. "  "
              .. C.rx   .. pad(fmt_bytes(total_rx), VW)
              .. "  "
              .. C.white .. pad(fmt_bytes(grand),    VW)
              .. "${font}" .. "\n"

    out = out .. C.tree .. "│\n"
    out = out .. C.tree .. "├── " .. C.val .. "max   : "
               .. C.white .. pad(fmt_bytes(max_tot), 10)
               .. C.label .. "  " .. max_label .. "\n"
    out = out .. C.tree .. "├── " .. C.val .. "min   : "
               .. C.white .. pad(fmt_bytes(min_tot), 10)
               .. C.label .. "  " .. min_label .. "\n"
    out = out .. C.tree .. "└── " .. C.val .. "avg   : "
               .. C.white .. pad(fmt_bytes(avg), 10)
               .. C.label .. "  (" .. fmt_bytes(grand) .. " / " .. shown .. ")\n"

    return out
end

-- ── build monthly/daily block ────────────────────────────────────────
local function daily_block(iface)
    local days = iface.traffic and iface.traffic.day
    if not days or #days == 0 then
        return C.tree .. "├── " .. C.dim .. "(no daily data)\n"
    end

    table.sort(days, function(a, b)
        local ta = (a.date and a.date.year or 0)*10000
                 + (a.date and a.date.month or 0)*100
                 + (a.date and a.date.day   or 0)
        local tb = (b.date and b.date.year or 0)*10000
                 + (b.date and b.date.month or 0)*100
                 + (b.date and b.date.day   or 0)
        return ta > tb
    end)

    local shown  = math.min(MAX_DAYS, #days)
    local total_rx, total_tx = 0, 0
    local max_tot, min_tot   = 0, math.huge
    local max_rx,  max_tx    = 0, 0
    local min_rx,  min_tx    = 0, 0
    local max_date, min_date = "", ""

    for i = 1, shown do
        local d   = days[i]
        local rx  = d.rx or 0
        local tx  = d.tx or 0
        local tot = rx + tx
        total_rx  = total_rx + rx
        total_tx  = total_tx + tx
        if tot > max_tot then
            max_tot  = tot; max_rx = rx; max_tx = tx
            max_date = string.format("%02d-%02d", d.date.month, d.date.day)
        end
        if tot < min_tot then
            min_tot  = tot; min_rx = rx; min_tx = tx
            min_date = string.format("%02d-%02d", d.date.month, d.date.day)
        end
    end

    local grand   = total_rx + total_tx
    local avg_rx  = (shown > 0) and (total_rx / shown) or 0
    local avg_tx  = (shown > 0) and (total_tx / shown) or 0
    local avg_tot = (shown > 0) and (grand    / shown) or 0

    -- same column layout as hourly block so the shared header aligns
    local LW, VW = 11, 10
    local function row(lbl, rx, tx, tot, last, lbl_color)
        local prefix = last and "└──" or "├──"
        return C.tree .. prefix .. " "
             .. (lbl_color or C.val) .. string.format("%-" .. LW .. "s", lbl)
             .. C.tx    .. pad(fmt_bytes(tx),  VW)
             .. "  "
             .. C.rx    .. pad(fmt_bytes(rx),  VW)
             .. "  "
             .. C.white .. pad(fmt_bytes(tot), VW)
             .. "\n"
    end

    local out = ""
    out = out .. C.tree .. "├─ " .. C.header .. "days   : "
               .. C.white .. (shown < MAX_DAYS and shown .. " of " .. MAX_DAYS .. " days" or MAX_DAYS .. " days") .. "\n"
    out = out .. C.tree .. "│\n"
    out = out .. row("max  " .. max_date, max_rx,   max_tx,   max_tot,   false)
    out = out .. row("min  " .. min_date, min_rx,   min_tx,   min_tot,   false)
    out = out .. row("avg",               avg_rx,   avg_tx,   avg_tot,   false)
    out = out .. "${font Monospace:bold:size=9}"
           .. row("total",            total_rx, total_tx, grand,     true, C.header):sub(1, -2)
           .. "${font}\n"
    return out
end

-- ── main entry point called by conky ────────────────────────────────
function conky_draw_vnstat()
    IFACE = var_NETWORK or IFACE   -- pick up interface from settings.lua at runtime
    local data = get_vnstat()
    if not data then
        return C.tree .. "┌─ " .. C.header
               .. "vnstat --- ERROR: no data\n"
               .. C.tree .. "└── " .. C.dim
               .. "is vnstat running? (vnstatd -d)\n"
    end

    -- find the right interface
    local iface = nil
    if data.interfaces then
        for _, v in ipairs(data.interfaces) do
            if v.name == IFACE then iface = v; break end
        end
    end
    if not iface then
        return C.tree .. "┌─ " .. C.header
               .. "vnstat --- interface " .. IFACE .. " not found\n"
    end

    -- grand totals for header
    local all_rx = iface.traffic and iface.traffic.total
                   and (iface.traffic.total.rx or 0) or 0
    local all_tx = iface.traffic and iface.traffic.total
                   and (iface.traffic.total.tx or 0) or 0
    local grand  = all_rx + all_tx

    local timestamp = os.date("%I:%M %p"):lower()

    local out = ""
    out = out .. C.tree .. "┌─ " .. C.header .. "vnstat"
               .. C.label .. "   Interface: " .. C.white .. IFACE
               .. C.label .. "   Total: "     .. C.white .. fmt_bytes(grand) .. "\n"
    out = out .. C.tree .. "│\n"
    out = out .. hourly_block(iface)
    out = out .. C.tree .. "│\n"
    out = out .. daily_block(iface)
    out = out .. C.tree .. "│\n"
    out = out .. C.tree .. "└─ " .. C.header
               .. "updated : " .. C.white .. timestamp .. "\n"

    return out
end
