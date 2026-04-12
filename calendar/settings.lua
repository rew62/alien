-- settings.lua - Configuration settings for calendar conky
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

    conky_w = 200 
    conky_h = 150 

    conky_title = "calendar"

    -- calendar settings
    cal_x = 15
    cal_y = 55
    cal_font = "DejaVu Sans"
    cal_title_size = 9
    cal_body_size = 11
    cal_body_color = "0xFFFFFF"
    cal_gaph = 28
    cal_gapt = 20
    cal_gapl = 18
    cal_sday = 0

    -- month title settings
    txt_x = 110
    txt_y = 25
    txt_font = "DejaVu Sans"
    txt_size = 12

    -- month colors
    local month_colors = {
        0xE57373, 0xF06292, 0xBA68C8, 0x9575CD,
        0x7986CB, 0x64B5F6, 0x4DD0E1, 0x4DB6AC,
        0x81C784, 0xAED581, 0xFFB74D, 0xA1887F,
    }
    local month = tonumber(os.date("%m"))
    mc = string.format("0x%06X", month_colors[month])
end
