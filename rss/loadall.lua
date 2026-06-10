-- loadall.lua - Loader for rss conky modules
--
-- v1.3 2026-06-10 @rew62

package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua"

local function try_require(modname)
    local ok, err = pcall(require, modname)
    if not ok then
        print("Error loading " .. modname .. ": " .. tostring(err))
        os.exit(1)
    end
end

--try_require("allcombined")
try_require("allcombined2")

local rss = require("rss")

local last_fetch = 0
local cwsize     = false

function conky_startup()
    conky_vars()
    rss.fetch()
    last_fetch = os.time()
end

function conky_mouse_hook(event)
    local t = event.type
    if t == "mouse_move" or t == "mouse_enter" or t == "mouse_leave" or t == "button_up" then return false end
    if t ~= "button_down" then return false end
    if event.button ~= "left" then return false end
    return rss.handle_click(event.y)
end

function conky_main()
    if conky_window == nil then return end
    if conky_window.width == 0 or conky_window.height == 0 then return end

    conky_draw_bg(bgtab)

    if os.time() - last_fetch >= rss.FETCH_INTERVAL then
        rss.fetch()
        last_fetch = os.time()
    end

    if not cwsize then
        print("Conky window initialized: " .. conky_window.width .. " x " .. conky_window.height)
        cwsize = true
    end
end
