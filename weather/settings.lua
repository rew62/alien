-- settings.lua - Configuration settings for weather conky
-- v1 04 2026-03-09 @rew62

package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua" 

theme = require("theme")

-- Overrides
--bg_color = 0xff0000
--bgtab = '{10,0,0,0,0,0x000000,0.7,3,2,0x2E8B57,1.0}'

-- fill in the rest from theme
for k, v in pairs(theme) do
    if _G[k] == nil then
        _G[k] = v
    end
end

--bgtab = theme.build_bgtab()
--print("bgtab: " .. bgtab)

conky_script_name = conky_config:match("([^/]+)$")
print("Script Name: " .. conky_script_name)

-- Weather widget type: "full" | "forecast" | "current"
if conky_script_name == "full.rc" then
    weather_type = "full"
    conky_title = "weather forecast"
end

if conky_script_name == "forecast.rc" then
    weather_type = "forecast"
    conky_title = "weather forecast"
end

if conky_script_name == "current.rc" then 
	weather_type = "current" 
	conky_title = "current conditions"
end

local sizes = {
    full     = { w = 302, h = 262 },
    forecast = { w = 310, h = 105 },
    current  = { w = 280, h = 105  },
}

-- Fallback to "full" if weather_type is nil or invalid
local selected = sizes[weather_type] or sizes["full"]

-- Export these as globals so loadall.lua can see them
target_width  = selected.w
target_height = selected.h

print(string.format("Target Dimensions for %s: %dx%d", weather_type, target_width, target_height))
