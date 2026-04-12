-- loadall.lua - Loader for gcal calendar conky modules
-- v1.1 2026-03-17 @rew62

-- === Load external modules ===
package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua" 

local cwsize      = false

local function try_require(modname)
    local ok, err = pcall(require, modname)
    if not ok then
        print("Error loading " .. modname .. ": " .. tostring(err))
        os.exit(1)
    end
end

try_require("allcombined2")
try_require("gcal2")

local BG_PADDING = 16  -- extra pixels below the last event row

function conky_main()
    if conky_window == nil then return end

    -- 1. Fetch + parse gcal data; get exact pixel height needed.
    local content_h = gcal_prefetch()

    -- 2. Patch bgtab: deserialise, override height (field 5), re-serialise.
    --    This works regardless of how bgtab is defined (conkyrc or here).
    local bt = load("return " .. bgtab)()
    bt[5] = content_h + BG_PADDING
    local parts = {}
    for i = 1, #bt do parts[i] = tostring(bt[i]) end
    local patched_bgtab = "{" .. table.concat(parts, ",") .. "}"

    -- 3. Draw background panel at the computed height, then overlay gcal.
    conky_draw_bg(patched_bgtab)
    conky_draw_gcal()

    -- One-time window size log
    if not cwsize and conky_window.width > 0 and conky_window.height > 0 then
        print("Conky window initialized: " .. conky_window.width .. " x " .. conky_window.height)
        cwsize = true
    end
end
