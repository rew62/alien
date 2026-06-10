-- rss.lua - RSS feed logic: feed cycling, fetch triggering, click dispatch
--
-- v1.0 2026-06-10 @rew62

local M = {}

local RSS_DIR   = os.getenv("HOME") .. "/.conky/alien/rss"
local CACHE_DIR = "/dev/shm/rss"
local FEEDS     = RSS_DIR .. "/feeds.conf"
local IDX_FILE  = CACHE_DIR .. "/feed_idx"
local MAP_FILE  = CACHE_DIR .. "/rss.map"

M.VOFFSET        = 18
M.LINE_HEIGHT    = 16
M.FETCH_INTERVAL = 600

local function count_feeds()
    local n = 0
    local f = io.open(FEEDS, "r")
    if not f then return 0 end
    for line in f:lines() do
        if not line:match("^%s*#") and not line:match("^%s*$") then n = n + 1 end
    end
    f:close()
    return n
end

local function read_idx()
    local f = io.open(IDX_FILE, "r")
    if not f then return 1 end
    local n = tonumber(f:read("*l")) or 1
    f:close()
    return n
end

local function write_idx(n)
    local f = io.open(IDX_FILE, "w")
    if f then f:write(n); f:close() end
end

function M.fetch()
    os.execute(RSS_DIR .. "/rss-fetch.sh &")
end

function M.next()
    local total = count_feeds()
    if total == 0 then return end
    write_idx((read_idx() % total) + 1)
    M.fetch()
end

function M.handle_click(y)
    local line_num = math.floor((y - M.VOFFSET) / M.LINE_HEIGHT) + 1
    if line_num < 1 then return false end

    local action
    local row = 0
    local f = io.open(MAP_FILE, "r")
    if not f then return false end
    for line in f:lines() do
        row = row + 1
        if row == line_num then
            action = line:match("^%d+|(.+)$")
            break
        end
    end
    f:close()

    if not action then return false end

    if action == "next" then
        M.next()
    else
        local safe = action:gsub("'", "'\\''")
        os.execute("xdg-open '" .. safe .. "' >/dev/null 2>&1 &")
    end

    return true
end

return M
