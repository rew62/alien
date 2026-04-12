-- loadall.lua - Loader for combined scripts (bars, background, calendar)
-- by @wim66
-- v4.1 2025-05-02 @rew62

-- === Load external modules ===
package.path = "./scripts/?.lua"
local function try_require(modname)
    local ok, err = pcall(require, modname)
    if not ok then
        print("Error loading " .. modname .. ": " .. tostring(err))
        os.exit(1)
    end
end
try_require("background")
--try_require("lua1-graphs")
--try_require("lua2-text")
--try_require("lua3-bars")
try_require("allcombined")

-- Main function called by lua_draw_hook_pre
function conky_main()
    conky_draw_background()
    --conky_draw_text()
    --conky_main_bars()
    --conky_draw_graph()
end
