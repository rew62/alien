-- settings.lua - Configuration settings for vnstat conky
-- v1.1 2026-04-06 @rew62

package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua" 

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

    conky_title = "vnstat"
end
