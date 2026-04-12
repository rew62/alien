-- loadall.lua - Loader for calendar conky modules
-- v1.1 2026-03-17 @rew62

-- === Load external modules ===
--package.path = "../scripts/?.lua"
package.path = "./?.lua;scripts/?.lua;../scripts/?.lua;" .. package.path
local cwsize      = false

local function try_require(modname)
    local ok, err = pcall(require, modname)
    if not ok then
        print("Error loading " .. modname .. ": " .. tostring(err))
        os.exit(1)
    end
    return mod
end

try_require("allcombined2")
try_require("hcal2")

function conky_main()
    if conky_window == nil then return end

    local txttab = string.format('{%d,%d,%s,1.0,"%s",%d,"c","%s"}',
        txt_x, txt_y, mc, txt_font, txt_size, os.date("%B %Y"))

    local caltab = string.format('{%d,%d,"%s",%d,%s,1.0,"%s",%d,%s,1.0,"%s",%d,%s,1.0," ",%d,%d,%d,%d}',
        cal_x, cal_y, cal_font, cal_title_size, mc, cal_font, cal_body_size, cal_body_color, cal_font, cal_body_size, mc, cal_gaph, cal_gapt, cal_gapl, cal_sday)

    conky_draw_bg(bgtab)
    if conky_script_name == "lcalendar.rc" then 
        conky_luacal(caltab)
        conky_luatext(txttab)
    end
    if conky_script_name == "hcal2.rc" then 
	conky_draw_calendar()
    end

    -- One-time window size log
    if not cwsize and conky_window.width > 0 and conky_window.height > 0 then
        print("Conky window initialized: " .. conky_window.width .. " x " .. conky_window.height)
        cwsize = true
    end
end
