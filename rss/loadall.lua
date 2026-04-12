-- loadall.lua - Loader for rss conky modules
--
-- v1.1 2026-03-17 @rew62

-- === Load external modules ===
--package.path = "../scripts/?.lua"
package.path = package.path .. ";./?.lua;../?.lua;scripts/?.lua;../scripts/?.lua" 


local cwsize         = false
local daemon_started = false

local function try_require(modname)
    local ok, err = pcall(require, modname)
    if not ok then
        print("Error loading " .. modname .. ": " .. tostring(err))
        os.exit(1)
    end
end

--try_require("allcombined")
try_require("allcombined2")

function conky_startup()
    conky_vars()  -- run the theme's variable setup as before
    local rss = os.getenv("HOME") .. "/.conky/alien/rss/rss-daemon.sh"
    --os.execute('pkill -f rss-daemon.sh 2>/dev/null; pkill -f "xdotool behave" 2>/dev/null; setsid ' .. rss .. ' &')
    os.execute('pkill -f rss-daemon.sh 2>/dev/null; pkill -f "xdotool behave" 2>/dev/null; ' .. rss .. ' &')
end

function conky_main()
    if conky_window == nil then return end


    if conky_window.width == 0 or conky_window.height == 0 then
        return
    end


    -- if not daemon_started then
    --     os.execute('pgrep -f rss-daemon.sh >/dev/null 2>&1 || ~/.conky/alien/rss/rss-daemon.sh &')                                             
    --     --local rss = os.getenv("HOME") .. "/.conky/alien/rss/rss-daemon.sh"                                                                     
    --     --os.execute('pkill -f rss-daemon.sh 2>/dev/null; pkill -f "xdotool behave" 2>/dev/null; sleep 1; ' .. rss .. ' &')                      
    --     daemon_started = true

    --     print("deamon started")
    -- end






    if not daemon_started then
        local rss = os.getenv("HOME") .. "/.conky/alien/rss/rss-daemon.sh"

        os.execute('pkill -f rss-daemon.sh 2>/dev/null')
        os.execute('bash "' .. rss .. '" >> /tmp/rss_test.log 2>&1 &')

        daemon_started = true
        print("daemon started (verified launch)")
    end











    -- 3. Draw background panel at the computed height, then overlay widget.
    conky_draw_bg(bgtab)

    -- One-time window size log
    if not cwsize and conky_window.width > 0 and conky_window.height > 0 then
        print("Conky window initialized: " .. conky_window.width .. " x " .. conky_window.height)
        cwsize = true
    end
end
