-- vnstat.lua - vnstat network statistics conky widget
-- v1.0 2026-04-04 @rew62

-- -----------------------------------------------------------------------
-- JSON DEPENDENCY FALLBACK
-- -----------------------------------------------------------------------
package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua"

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

local IFACE      = "wlp2s0"    -- change to your interface
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
    reset   = "${color}",
}

-- ── unit formatting ─────────────────────────────────────────────────
local function fmt_bytes(b)
    b = tonumber(b) or 0
    if     b >= 1e12 then return string.format("%.2fTB", b / 1e12)
    elseif b >= 1e9  then return string.format("%.2fGB", b / 1e9)
    elseif b >= 1e6  then return string.format("%.2fMB", b / 1e6)
    elseif b >= 1e3  then return string.format("%.2fKB", b / 1e3)
    else                  return string.format("%.0fB",  b)
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
        local rx = (h.rx or 0) * 1024
        local tx = (h.tx or 0) * 1024
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
    out = out .. C.tree .. "├── " .. C.label .. "interface : "
               .. C.val  .. IFACE .. "\n"
    out = out .. C.tree .. "│\n"
    out = out .. C.tree .. "├── " .. C.label .. "24 hours  : "
               .. C.val  .. shown .. " entries (hourly)"
               .. C.dim  .. " ~ " .. shown .. " shown @ 0\n"
    out = out .. C.tree .. "│\n"
    out = out .. C.tree .. "├──── " .. C.label .. "max   : "
               .. C.val  .. pad(fmt_bytes(max_tot), 10)
               .. C.dim  .. " ~ " .. max_label .. "\n"
    out = out .. C.tree .. "├──── " .. C.label .. "min   : "
               .. C.val  .. pad(fmt_bytes(min_tot), 10)
               .. C.dim  .. " ~ " .. min_label .. "\n"
    out = out .. C.tree .. "├──── " .. C.label .. "avg   : "
               .. C.val  .. pad(fmt_bytes(avg), 10)
               .. C.dim  .. " = (" .. fmt_bytes(grand) .. " / " .. shown .. ")\n"
    out = out .. C.tree .. "├──── " .. C.label .. "total : "
               .. C.val  .. pad(fmt_bytes(grand), 10)
               .. C.dim  .. " = (TX " .. fmt_bytes(total_tx)
               .. " + RX " .. fmt_bytes(total_rx) .. ")\n"
    out = out .. C.tree .. "│\n"

    -- per-hour rows
    for i = 1, shown do
        local h   = hours[i]
        local rx  = (h.rx or 0) * 1024
        local tx  = (h.tx or 0) * 1024
        local tot = rx + tx
        local prefix = (i == shown) and "└────" or "├────"
        out = out .. C.tree  .. prefix .. " "
                  .. C.dim   .. string.format("Hr: %02d ", h.time.hour)
                  .. C.rx    .. "<RX " .. pad(fmt_bytes(rx),  10)
                  .. C.dim   .. " + "
                  .. C.tx    .. "TX "  .. pad(fmt_bytes(tx),   9)
                  .. C.dim   .. " = TOT "
                  .. C.val   .. pad(fmt_bytes(tot), 10)
                  .. "\n"
    end

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
    local max_label, min_label = "", ""

    for i = 1, shown do
        local d   = days[i]
        local rx  = (d.rx or 0) * 1024
        local tx  = (d.tx or 0) * 1024
        local tot = rx + tx
        total_rx  = total_rx + rx
        total_tx  = total_tx + tx
        local lbl = string.format("[%04d-%02d-%02d - %04d-%02d-%02d]",
            d.date.year, d.date.month, d.date.day,
            d.date.year, d.date.month, d.date.day + 1)
        if tot > max_tot then max_tot = tot; max_label = lbl end
        if tot < min_tot then min_tot = tot; min_label = lbl end
    end

    local grand = total_rx + total_tx
    local avg   = (shown > 0) and (grand / shown) or 0

    local out = ""
    out = out .. C.tree .. "├── " .. C.label .. "days      : "
               .. C.val  .. shown .. " / " .. MAX_DAYS .. " entries (daily)\n"
    out = out .. C.tree .. "│\n"
    out = out .. C.tree .. "├──── " .. C.label .. "max   : "
               .. C.val  .. pad(fmt_bytes(max_tot), 10)
               .. C.dim  .. " ~ " .. max_label .. "\n"
    out = out .. C.tree .. "├──── " .. C.label .. "min   : "
               .. C.val  .. pad(fmt_bytes(min_tot), 10)
               .. C.dim  .. " ~ " .. min_label .. "\n"
    out = out .. C.tree .. "├──── " .. C.label .. "avg   : "
               .. C.val  .. pad(fmt_bytes(avg), 10)
               .. C.dim  .. " = (" .. fmt_bytes(grand) .. " / " .. shown .. ")\n"
    out = out .. C.tree .. "└──── " .. C.label .. "total : "
               .. C.val  .. pad(fmt_bytes(grand), 10)
               .. C.dim  .. " = (TX " .. fmt_bytes(total_tx)
               .. " + RX " .. fmt_bytes(total_rx) .. ")\n"
    return out
end

-- ── main entry point called by conky ────────────────────────────────
function conky_draw_vnstat()
    local data = get_vnstat()
    if not data then
        return C.tree .. "┌─── " .. C.header
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
        return C.tree .. "┌─── " .. C.header
               .. "vnstat --- interface " .. IFACE .. " not found\n"
    end

    -- grand totals for header
    local all_rx = iface.traffic and iface.traffic.total
                   and (iface.traffic.total.rx or 0) * 1024 or 0
    local all_tx = iface.traffic and iface.traffic.total
                   and (iface.traffic.total.tx or 0) * 1024 or 0
    local grand  = all_rx + all_tx

    local timestamp = os.date("%H:%M:%S")

    local out = ""
    out = out .. C.tree .. "┌─── " .. C.header
               .. "vnstat --- TOTAL: " .. fmt_bytes(grand) .. "\n"
    out = out .. C.tree .. "│\n"
    out = out .. hourly_block(iface)
    out = out .. C.tree .. "│\n"
    out = out .. daily_block(iface)
    out = out .. C.tree .. "│\n"
    out = out .. C.tree .. "└── " .. C.label
               .. "updated : " .. C.val .. timestamp .. "\n"

    return out
end
