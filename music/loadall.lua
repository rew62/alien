-- loadall.lua - Loader for music conky modules
-- v1.3 2026-05-19 @rew62

package.path = "./?.lua;scripts/?.lua;../scripts/?.lua;" .. package.path

local cwsize      = false
local update_func = nil
local draw_func   = nil

local function try_require(modname)
    local ok, err = pcall(require, modname)
    if not ok then
        print("Error loading " .. modname .. ": " .. tostring(err))
        os.exit(1)
    end
end

try_require("allcombined2")

-- ── Conky hooks ───────────────────────────────────────────────────────────────

-- startup hook: 'vars' (called once by Conky after lua_load)
-- settings.lua defines conky_vars() for title/name; we extend it here

local _settings_vars = conky_vars
function conky_vars()
    if _settings_vars then _settings_vars() end
    if update_func then update_func() end
end

function conky_main()
    if conky_window == nil then return end

    if bgtab then conky_draw_bg(bgtab) end

    if draw_func then draw_func() end

    if not cwsize and conky_window.width > 0 and conky_window.height > 0 then
        print("Conky window initialized: " .. conky_window.width .. " x " .. conky_window.height)
        cwsize = true
    end
end
