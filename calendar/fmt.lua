-- fmt.lua - Fixed-width formatting helpers for conky
-- v1.1 2026-04-09 @rew62

local FIGSP = "\xe2\x80\x87"  -- U+2007 FIGURE SPACE (digit-width space)

-- Percentage formatter: 0-100, no decimals, always 3 digit-widths
function conky_fmtpct(...)
    local val = conky_parse("${" .. table.concat({...}, " ") .. "}")
    local n = tonumber(val) or 0
    local s = string.format("%d", n)
    return string.rep(FIGSP, 3 - #s) .. s
end

function conky_fmtspeed(iface, dir)
    local var = dir == "up" and "${upspeedf " .. iface .. "}" or "${downspeedf " .. iface .. "}"
    local val = conky_parse(var)
    local n = tonumber(val) or 0
    local s
    if n >= 1000 then
        s = string.format("%.0f", n)
    else
        s = string.format("%.1f", n)
    end
    return string.rep(FIGSP, 5 - #s) .. s
end
