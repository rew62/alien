-- stocks.lua - Self-contained stock quote table widget for Conky
-- Reads symbols.conf, fetches from Finnhub, caches to /dev/shm, renders table
-- v3.0 2026-04-13 @rew62

local HOME      = os.getenv("HOME")
local CACHE_DIR = "/dev/shm/stock_cache"
local CACHE_TTL = 120
local ENV_FILE  = HOME .. "/.conky/alien/.env"
local CONF_DIR  = HOME .. "/.conky/alien/stocks"

-- ── Colors ────────────────────────────────────────────────────────────
local C = {
    border = "${color #4a6274}",
    header = "${color #8ab4c8}",
    text   = "${color #dce6ec}",
    pos    = "${color #50fa7b}",
    neg    = "${color #ff5555}",
    reset  = "${color}",
}

-- ── Available column definitions ──────────────────────────────────────
-- key:     Finnhub JSON field (nil = symbol name)
-- fmt:     format string for numeric values (nil = raw string)
-- colored: true = green/red based on sign
local COL_DEFS = {
    symbol = { label = "Symbol", w = 10, align = "left",  key = nil,  fmt = nil,     colored = false },
    last   = { label = "Last",   w = 10, align = "right", key = "c",  fmt = "%.2f",  colored = false },
    open   = { label = "Open",   w = 8,  align = "right", key = "o",  fmt = "%.2f",  colored = false },
    high   = { label = "High",   w = 8,  align = "right", key = "h",  fmt = "%.2f",  colored = false },
    low    = { label = "Low",    w = 8,  align = "right", key = "l",  fmt = "%.2f",  colored = false },
    change = { label = "Change", w = 10, align = "right", key = "d",  fmt = "%+.2f", colored = true  },
}

-- ── Configure display columns here ───────────────────────────────────
local COLUMNS = { "symbol", "last", "change" }

-- ── API key ───────────────────────────────────────────────────────────

local _api_key = nil

local function load_api_key()
    if _api_key then return _api_key end
    local f = io.open(ENV_FILE, "r")
    if not f then return nil end
    for line in f:lines() do
        local val = line:match("^FINNHUB_API_KEY=(.+)$")
        if val then
            _api_key = val:match("^%s*(.-)%s*$")
            break
        end
    end
    f:close()
    return _api_key
end

-- ── Cache helpers ─────────────────────────────────────────────────────

local function cache_age(symbol)
    local f = io.popen("stat -c %Y " .. CACHE_DIR .. "/" .. symbol .. ".json 2>/dev/null")
    if not f then return math.huge end
    local mtime = tonumber(f:read("*l") or "")
    f:close()
    return mtime and (os.time() - mtime) or math.huge
end

local function read_cache(symbol)
    local f = io.open(CACHE_DIR .. "/" .. symbol .. ".json", "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

-- ── Fetch (non-blocking, background curl) ────────────────────────────

local function fetch_symbol(symbol, key)
    local url   = string.format(
        "https://finnhub.io/api/v1/quote?symbol=%s&token=%s", symbol, key)
    local cache = CACHE_DIR .. "/" .. symbol .. ".json"
    -- curl in background; only write cache if response contains valid non-zero price
    local cmd = string.format(
        [[bash -c 'D=$(curl -s --max-time 10 "%s"); ]]
        .. [[echo "$D" | jq -e ".c != null and .c != 0" >/dev/null 2>&1 ]]
        .. [[&& echo "$D" > "%s"' &]],
        url, cache)
    os.execute(cmd)
end

local function refresh_stale(symbols, key)
    for _, sym in ipairs(symbols) do
        if cache_age(sym) >= CACHE_TTL then
            fetch_symbol(sym, key)
        end
    end
end

-- ── Symbol list ───────────────────────────────────────────────────────

local function read_symbols()
    local symbols = {}
    local f = io.open(CONF_DIR .. "/symbols.conf", "r")
    if not f then return symbols end
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            table.insert(symbols, line)
        end
    end
    f:close()
    return symbols
end

-- ── JSON parse ────────────────────────────────────────────────────────

local function parse_val(json, key)
    if not json then return nil end
    local val = json:match('"' .. key .. '":([%-]?[%d%.]+)')
    return val and tonumber(val)
end

-- ── Table rendering ───────────────────────────────────────────────────

local function seg(n)
    return string.rep("─", n)
end

local function hline(l, m, r)
    local s = C.border .. l
    for i, name in ipairs(COLUMNS) do
        local col = COL_DEFS[name]
        s = s .. seg(col.w + 2)
        s = s .. (i < #COLUMNS and m or r)
    end
    return s .. C.reset .. "\n"
end

local function header_row()
    local s = C.border .. "│"
    for _, name in ipairs(COLUMNS) do
        local col = COL_DEFS[name]
        local fmt = col.align == "left" and ("%-"..col.w.."s") or ("%"..col.w.."s")
        s = s .. " " .. C.header .. string.format(fmt, col.label) .. " " .. C.border .. "│"
    end
    return s .. C.reset .. "\n"
end

local function data_row(data)
    local s = C.border .. "│"
    for _, name in ipairs(COLUMNS) do
        local col  = COL_DEFS[name]
        local val  = col.key and data[col.key] or data.symbol
        local raw  = tonumber(val)

        local display
        if col.fmt and raw then
            display = string.format(col.fmt, raw)
        else
            display = val or "--"
        end

        local color = C.text
        if col.colored and raw then
            color = raw < 0 and C.neg or C.pos
        end

        local fmt = col.align == "left" and ("%-"..col.w.."s") or ("%"..col.w.."s")
        s = s .. " " .. color .. string.format(fmt, display) .. " " .. C.border .. "│"
    end
    return s .. C.reset .. "\n"
end

-- ── Main entry point ──────────────────────────────────────────────────

function conky_draw_stocks()
    os.execute("mkdir -p " .. CACHE_DIR)

    local key     = load_api_key()
    local symbols = read_symbols()

    if #symbols == 0 then
        return C.neg .. "(no symbols in symbols.conf)" .. C.reset
    end
    if not key then
        return C.neg .. "(FINNHUB_API_KEY not found in .env)" .. C.reset
    end

    refresh_stale(symbols, key)

    local out = ""
    out = out .. hline("┌", "┬", "┐")
    out = out .. header_row()
    out = out .. hline("├", "┼", "┤")

    for i, sym in ipairs(symbols) do
        local json = read_cache(sym)
        local row  = {
            symbol = sym,
            c = parse_val(json, "c"),
            o = parse_val(json, "o"),
            h = parse_val(json, "h"),
            l = parse_val(json, "l"),
            d = parse_val(json, "d"),
        }
        out = out .. data_row(row)
        if i < #symbols then
            out = out .. hline("├", "┼", "┤")
        end
    end

    out = out .. hline("└", "┴", "┘")
    return out
end
