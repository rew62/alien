-- loadall.lua - Loader for conky modules
-- v1.1 2026-03-17 @rew62

-- Load external modules 
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

function conky_main()
    if conky_window == nil then return end

    conky_draw_bg(bgtab)

    -- One-time window size log
    if not cwsize and conky_window.width > 0 and conky_window.height > 0 then
        print("Conky window initialized: " .. conky_window.width .. " x " .. conky_window.height)
        cwsize = true
    end
end
