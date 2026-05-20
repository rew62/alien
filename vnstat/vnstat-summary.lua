-- vnstat-summary.lua - vnstat day / week / month summary conky widget
-- v1.0 2026-05-10 @rew62

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

local C = {
    sep    = "${color5}",
    header = "${color6}",
    label  = "${color}",
    val    = "${color1}",
    dim    = "${color4}",
    rx     = "${color3}",
    tx     = "${color2}",
    white  = "${color e8e8e8}",
}

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

local function get_vnstat(iface)
    local pipe = io.popen("vnstat -i " .. iface .. " --json 2>/dev/null")
    if not pipe then return nil end
    local raw = pipe:read("*a")
    pipe:close()
    if not raw or raw == "" then return nil end
    local decoded_ok, data = pcall(cjson.decode, raw)
    if not decoded_ok then return nil end
    return data
end

-- Returns today's date table and the date table for the start of the current week.
-- var_WEEK_START: "sunday" (default) or "monday"
local function week_range()
    local today = os.date("*t")
    -- os.date wday: 1=Sun 2=Mon ... 7=Sat
    local start_wday = (var_WEEK_START == "monday") and 2 or 1
    local days_since_start = (today.wday - start_wday + 7) % 7
    local start_ts = os.time(today) - days_since_start * 86400
    local week_start = os.date("*t", start_ts)
    return today, week_start
end

local function date_num(d)
    return d.year * 10000 + d.month * 100 + d.day
end

function conky_draw_vnstat_summary()
    local iface_name = var_NETWORK or "wlp2s0"
    local data = get_vnstat(iface_name)

    if not data then
        return C.tree .. "┌─── " .. C.header .. "vnstat summary --- ERROR\n"
             .. C.tree .. "└── " .. C.dim .. "no data (is vnstatd running?)\n"
    end

    local iface = nil
    if data.interfaces then
        for _, v in ipairs(data.interfaces) do
            if v.name == iface_name then iface = v; break end
        end
    end
    if not iface then
        return C.tree .. "┌─── " .. C.header .. "vnstat summary\n"
             .. C.tree .. "└── " .. C.dim .. "interface " .. iface_name .. " not found\n"
    end

    local today, monday = week_range()
    local today_n  = date_num(today)
    local monday_n = date_num(monday)

    -- ── today ──────────────────────────────────────────────────────────
    local day_rx, day_tx = 0, 0
    for _, d in ipairs(iface.traffic.day or {}) do
        if date_num(d.date) == today_n then
            day_rx = d.rx or 0
            day_tx = d.tx or 0
            break
        end
    end

    -- ── this week  (Monday → today) ────────────────────────────────────
    local week_rx, week_tx = 0, 0
    for _, d in ipairs(iface.traffic.day or {}) do
        local n = date_num(d.date)
        if n >= monday_n and n <= today_n then
            week_rx = week_rx + (d.rx or 0)
            week_tx = week_tx + (d.tx or 0)
        end
    end

    -- ── this month ────────────────────────────────────────────────────
    local mon_rx, mon_tx = 0, 0
    for _, m in ipairs(iface.traffic.month or {}) do
        if m.date.year == today.year and m.date.month == today.month then
            mon_rx = m.rx or 0
            mon_tx = m.tx or 0
            break
        end
    end

    -- column widths: label=6 chars left-aligned, values=12 chars right-aligned
    local LW  = 6
    local VW  = 12
    local SEP = string.rep("─", LW + VW + VW)

    local function row(label, rxval, txval)
        return C.val .. string.format("%-" .. LW .. "s", label)
             .. C.tx   .. pad(fmt_bytes(txval), VW)
             .. C.rx   .. pad(fmt_bytes(rxval), VW)
             .. "\n"
    end

    local timestamp = os.date("%I:%M %p"):lower()

    local out = ""
    out = out .. C.header .. string.format("%-" .. (LW + VW) .. "s", "vnstat")
              .. C.white  .. pad(iface_name, VW) .. "\n"
    out = out .. "${voffset 8}"
    out = out .. string.rep(" ", LW)
              .. C.tx     .. pad("Upload",   VW)
              .. C.rx     .. pad("Download", VW)
              .. "\n"
    out = out .. C.sep    .. SEP .. "\n"
    out = out .. row("today",  day_rx,  day_tx)
    out = out .. row("week",   week_rx, week_tx)
    out = out .. row("month",  mon_rx,  mon_tx)
    out = out .. C.sep    .. SEP .. "\n"
    out = out .. C.header .. "updated : "
              .. C.white  .. timestamp

    return out
end
