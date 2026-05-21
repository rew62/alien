-- loadall.lua - Loader for weather conky modules
-- v1.6 2026-03-25 @rew62 (Refactored)

-- package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua"
package.path = package.path .. ";./?.lua;../?.lua;" .. (os.getenv("HOME") or "") .. "/.conky/alien/scripts/?.lua"

-- Logic Variables
local update_func = nil
local draw_func   = nil
local cwsize      = false

-- -----------------------------------------------------------------------
-- JSON DEPENDENCY FALLBACK
-- -----------------------------------------------------------------------
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

-- Helper function for safe loading
local function try_require(modname)
    local ok, err = pcall(require, modname)
    if not ok then
        print("ERROR: could not load '" .. modname .. "': " .. tostring(err))
    end
    return ok
end

-- Initial Setup
try_require("allcombined2")
print("Lua Version: " .. _VERSION)
-- Function Mapping
local dispatch = {
    ["owm_current_top.rc"] = {
        mods = {"owm_fetch", "draw_owm_current_top"},
        upd  = "conky_owm_fetch",
        drw  = "conky_weather_current",
    },
    ["owm_current_sidepanel.rc"] = {
        mods = {"owm_fetch", "draw_owm_current_sidepanel"},
        upd  = "conky_owm_fetch",
        drw  = "conky_weather_current",
    },
    ["nws_forecast_small.rc"] = {
        mods = {"nws_fetch", "draw_nws_forecast_small"},
        upd  = "weather_update",
        drw  = "conky_weather_main",
    },
    ["nws_forecast_sidepanel.rc"] = {
        mods = {"nws_fetch", "draw_nws_forecast_sidepanel"},
        upd  = "weather_update",
        drw  = "conky_weather_main",
    },
    ["full.rc"] = {
        mods = {"nws_fetch", "owm_fetch", "draw_owm_nws_full"},
        upd  = "weather_update",
        drw  = "conky_weather_main",
    },
}

local d = dispatch[conky_script_name] or dispatch["full.rc"]
local ok = true
for _, mod in ipairs(d.mods) do ok = ok and try_require(mod) end
if ok then
    update_func = _G[d.upd]
    draw_func   = _G[d.drw]
end

-- Conky Hooks

-- This satisfies 'lua_startup_hook = weather_update' in your .rc
function conky_weather_update()
    if update_func then 
        update_func() 
    else
        print("WARNING: No update function mapped for " .. tostring(conky_script_name))
    end
end

function conky_main()
    if conky_window == nil then return end

    -- Apply the dimensions from settings.lua
    if conky_window.width ~= target_width or conky_window.height ~= target_height then
        conky_window.width = target_width
        conky_window.height = target_height
    end

    -- Draw background (if exists)
    if conky_draw_bg then
        conky_draw_bg(bgtab)
    end

    -- Run the mapped Update & Draw functions
    if update_func then update_func() end
    if draw_func   then draw_func()   end

    -- One-time initialization log
    if not cwsize then
        print("Window resized to target: " .. conky_window.width .. " x " .. conky_window.height)
        cwsize = true
    end
end
