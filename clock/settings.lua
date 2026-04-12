-- settings.lua - Configuration settings for clock conky
-- v1 04 2026-03-09 @rew62

package.path = package.path .. ";../?.lua"

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

function conky_vars()
    conky_script_name = conky_config:match("([^/]+)$")
    print("Script Name: " .. conky_script_name)

    conky_title = "clock"
end

--[[
local bgtab=load("return" .. bgtab)()
local r = bgtab[1] -- corner radius
local x = bgtab[2] -- x position
local y = bgtab[3] -- y position
local w = bgtab[4] -- width (0 = full window width)
local h = bgtab[5] -- height (0 = full window height)
local color = bgtab[6] -- fill color (hex)
local alpha = bgtab[7] -- fill alpha
local draw = bgtab[8] -- 1=fill, 2=stroke only, 3=fill+stroke outline
local lwidth = bgtab[9] -- line width (for stroke/outline)
local olcolor= bgtab[10] -- outline color (hex)
local olalpha= bgtab[11] -- outline alpha 
--]]
