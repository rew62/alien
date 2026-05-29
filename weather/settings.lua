-- settings.lua - Configuration settings for weather conky
-- v1 04 2026-03-09 @rew62

package.path = package.path .. ";../?.lua"
--package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua" 

theme = require("theme")

-- override just one thing
--bg_color = 0xff0000
--bgtab = '{10,0,0,0,0,0x000000,0.7,3,2,0x2E8B57,1.0}'

-- fill in the rest from theme
for k, v in pairs(theme) do
    if _G[k] == nil then
        _G[k] = v
    end
end

conky_script_name = conky_config:match("([^/]+)$")
print("Script Name: " .. conky_script_name)

if conky_script_name == "full.rc"                  then conky_title = "weather"             end
if conky_script_name == "nws_forecast_small.rc"       then conky_title = "weather forecast" end
if conky_script_name == "nws_forecast_sidepanel.rc"   then conky_title = "weather forecast" end
if conky_script_name == "owm_current_top.rc"       then conky_title = "current conditions"  end
if conky_script_name == "owm_current_sidepanel.rc" then conky_title = "current conditions"  end

local sizes = {
    ["full.rc"]                  = { w = 302, h = 262 },
    ["nws_forecast_small.rc"]      = { w = 310, h = 105 },
    ["nws_forecast_sidepanel.rc"]  = { w = 321, h = 178 },
    ["owm_current_top.rc"]       = { w = 280, h = 105 },
    ["owm_current_sidepanel.rc"] = { w = 325, h = 125 },
}

local selected = sizes[conky_script_name] or sizes["full.rc"]
target_width  = selected.w
target_height = selected.h
print(string.format("Target Dimensions: %dx%d", target_width, target_height))

