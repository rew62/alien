-- owm-fetch.lua - OWM data reader for conky weather widgets
-- Fetch handled by owm_fetch.sh; all callers share one cache
-- v1.1 2026-04-09 @rew62
-- PUBLIC API:
--   conky_owm_fetch()   -- trigger background fetch if cache is stale
--   owm_get(field)      -- read one field from owm_parsed.txt (pure Lua, no subprocess)
--
-- Cache location: /dev/shm/conky/owm_parsed.txt
--
-- v2.0 2026-04-01 (Refactored: fetch moved to shared owm_fetch.sh)

local CACHE_JSON   = "/dev/shm/conky/owm_current.json"
local CACHE_PARSED = "/dev/shm/conky/owm_parsed.txt"
local CACHE_TTL    = 300   -- seconds; must match owm_fetch.sh CACHE_TTL
local FETCH_SCRIPT = os.getenv("HOME") .. "/.conky/alien/scripts/owm_fetch.sh"

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

local function file_age_seconds(path)
    local f = io.open(path, "r")
    if not f then return math.huge end
    f:close()
    local h = io.popen("stat -c %Y " .. path .. " 2>/dev/null")
    if not h then return math.huge end
    local mtime = tonumber(h:read("*l")); h:close()
    if not mtime then return math.huge end
    return os.time() - mtime
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- owm_get(field)
-- Read a single field from owm_parsed.txt directly in Lua.
-- Returns the value string, or "N/A" if not found.
function owm_get(field)
    local raw = read_file(CACHE_PARSED)
    if not raw then return "N/A" end
    local val = raw:match("\n" .. field .. "=([^\n]+)")
                or raw:match("^"  .. field .. "=([^\n]+)")
    return val or "N/A"
end

-- conky_owm_fetch()
-- Call from loadall.lua inside conky_main() or as lua_startup_hook.
-- Checks cache age, then delegates to owm_fetch.sh for background fetch.
function conky_owm_fetch()
    if file_age_seconds(CACHE_JSON) < CACHE_TTL then
        return  -- cache still fresh
    end
    -- owm_fetch.sh handles its own lock, so calling it here is safe even if
    -- multiple conky instances are running.
    os.execute(FETCH_SCRIPT .. " > /dev/null 2>&1 &")
end

-- ── Standalone self-test ──────────────────────────────────────────────────────
-- Run:  lua owm-fetch.lua
-- Dumps owm_parsed.txt to stdout.
if not conky_parse then
    print("=== OWM Reader Self-Test ===")
    print("Triggering fetch via owm_fetch.sh ...")
    os.execute(FETCH_SCRIPT)
    local out = read_file(CACHE_PARSED)
    if out then
        print(out)
    else
        print("No data yet — check owm_fetch.log and your .env")
    end
end
