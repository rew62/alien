-- fmt.lua - Fixed-width formatting helpers for conky
-- v1.1 2026-04-09 @rew62

-- Percentage formatter: 0-100, no decimals, always 3 chars ("  1", " 10", "100")
function conky_fmtpct(...)
    local val = conky_parse("${" .. table.concat({...}, " ") .. "}")
    local n = tonumber(val) or 0
    return string.format("%2d", n)
end

function conky_fmtspeed(iface, dir)
    local var = dir == "up" and "${upspeedf " .. iface .. "}" or "${downspeedf " .. iface .. "}"
    local val = conky_parse(var)
    local n = tonumber(val) or 0
    if n >= 1000 then
        return string.format("%5.0f", n)
    else
        return string.format("%5.1f", n)
    end
end
