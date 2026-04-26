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
print("Detected Weather Type: " .. tostring(weather_type))

-- Function Mapping - maps weather modes to 'update' and 'draw' variables so conky_main doesn't have to check the weather_type every second.

if weather_type == "current" then
    if try_require("owm-fetch") and try_require("alien-weather-current") then
        update_func = conky_owm_fetch
        draw_func   = conky_weather_current
    end
elseif weather_type == "forecast" then
    if try_require("nws_weather") and try_require("alien-weather-forecast") then
        update_func = weather_update or conky_weather_update
        draw_func   = conky_weather_main
    end
else -- Default to "full"
    if try_require("nws_weather") and try_require("alien-weather-full") then
        update_func = weather_update or conky_weather_update
        draw_func   = conky_weather_main
    end
end

-- Conky Hooks

-- This satisfies 'lua_startup_hook = weather_update' in your .rc
function conky_weather_update()
    if update_func then 
        update_func() 
    else
        print("WARNING: No update function mapped for " .. tostring(weather_type))
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
