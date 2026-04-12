-- gcal2.lua - draws gcalcli agenda output as grouped day sections (variant 2)
-- v1.1 2026-04-05 @rew62

require 'cairo'

-- ── tunables ────────────────────────────────────────────────────────────────
local FONT_HEADER   = "Ubuntu"          -- date header font
local FONT_BODY     = "Ubuntu"          -- event body font
local SIZE_HEADER   = 11
local SIZE_BODY     = 11
local SIZE_TIME     = 10
local SIZE_LOCATION = 9

local COLOR_HEADER   = {0.67, 0.84, 1.00, 1.0}   -- light-blue date labels
local COLOR_DIVIDER  = {0.40, 0.60, 0.85, 0.55}   -- subtle blue-white line
local COLOR_BULLET   = {0.75, 0.90, 1.00, 0.85}   -- bullet dot
local COLOR_EVENT    = {1.00, 1.00, 1.00, 0.90}   -- event text
local COLOR_TIME     = {0.67, 0.84, 1.00, 0.75}   -- time / length text (dimmer)
local COLOR_LOCATION = {0.67, 0.84, 1.00, 0.55}   -- location text (dimmest)

local X             = 10    -- left margin (relative to conky window)
local Y_START       = 20    -- top padding
local LINE_H        = 18    -- pixels per event row
local HEADER_H      = 24    -- pixels per date-group header
local DIVIDER_W     = 280   -- width of the horizontal rule
local BULLET_OFFSET = 8     -- x offset for bullet dot
local EVENT_OFFSET  = 16    -- x offset for event text
local TIME_X        = 200   -- x position of time column
local LENGTH_X      = 260   -- x position of length column

-- ── module-level cache (populated by gcal_prefetch before bg is drawn) ───────
local _cache = { days = nil, height = 0 }

-- ── helpers ──────────────────────────────────────────────────────────────────
local function set_color(cr, c)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
end

local function draw_text(cr, font, size, bold, x, y, text)
    cairo_select_font_face(cr, font,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, text)
end

local function draw_divider(cr, x, y, w)
    set_color(cr, COLOR_DIVIDER)
    cairo_set_line_width(cr, 0.6)
    cairo_move_to(cr, x, y)
    cairo_line_to(cr, x + w, y)
    cairo_stroke(cr)
end

local function draw_bullet(cr, x, y)
    set_color(cr, COLOR_BULLET)
    cairo_arc(cr, x, y - 3.5, 2.2, 0, 2 * math.pi)
    cairo_fill(cr)
end

-- ── gcalcli parser ───────────────────────────────────────────────────────────

local function strip_ansi(s)
    s = s:gsub("\027%[[%d;]*%a", "")
    return s
end

-- local function parse_date_label(raw)
--     raw = raw:match("^%s*(.-)%s*$")
--     if raw == "" then return nil end
--     if raw:match("^%a%a%a %a%a%a %d") then
--         return raw:upper()
--     end
--     return nil
-- end

local function parse_date_label(raw)                                                                            
    raw = raw:match("^%s*(.-)%s*$")                                                                             
    if raw == "" then return nil end                                                                            
                                                                                                                
    -- Match standard gcalcli header: "Mon Apr  6" (with optional comma)                                        
    if raw:match("^%a%a%a,? %a%a%a %d") then                                                                    
        local upper = raw:upper()                                                                               
                                                                                                                
        -- Extract Month and Day for date math                                                                  
        -- %a%a%a,? handles the weekday; %s+ handles one or more spaces                                         
        local m_name, d_num = upper:match("^%a%a%a,?%s+(%a%a%a)%s+(%d+)")                                       
        local months = {
            JAN=1, FEB=2, MAR=3, APR=4, MAY=5, JUN=6,
            JUL=7, AUG=8, SEP=9, OCT=10, NOV=11, DEC=12
        }

        if m_name and d_num and months[m_name] then
            local now = os.date("*t")
            local m = months[m_name]
            local d = tonumber(d_num)
            local y = now.year

            -- Simple year rollover check (e.g., today is Dec 31, header is Jan 2)
            if now.month == 12 and m == 1 then y = y + 1 end

            -- Calculate timestamps (using noon to avoid Daylight Savings edge cases)
            local header_ts = os.time({year=y, month=m, day=d, hour=12})
            local today_ts  = os.time({year=now.year, month=now.month, day=now.day, hour=12})
            local diff = math.floor((header_ts - today_ts) / 86400 + 0.5)

            if diff > 0 then
                -- Append the day count to the header 
                return string.format("%s (+%d Day%s)", upper, diff, diff > 1 and "s" or "")
            end
        end
        
        return upper
    end
    return nil
end

local function run_gcalcli()
    --local f = io.popen("gcalcli agenda today '24 days' --details location --details length")
    local f = io.popen("gcalcli agenda today '14 days' --details location --details length")
    if not f then return "" end
    local raw = f:read("*a")
    f:close()
    return raw
end

local function parse(raw)
    -- Returns list of { header=string, events={ {text, time, length, location}, ... } }
    local days = {}
    local current   = nil
    local last_event = nil

    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        local clean = strip_ansi(line)

        local left  = clean:sub(1, 12)
        local right = clean:sub(13)

        left  = left:match("^%s*(.-)%s*$")
        right = right:match("^%s*(.-)%s*$")

        if right == "" and left == "" then
            -- blank line — ignore

        elseif right:match("^Length:") then
            -- attach length to the previous event; skip all-day durations
            if last_event then
                local val = right:match("^Length:%s*(.+)$") or ""
                local ndays = val:match("^(%d+) days?")
                if ndays then
                    if tonumber(ndays) > 1 then
                        last_event.time = ndays .. " days"
                    end
                else
                    last_event.length = val:gsub(":00$", "")
                end
            end

        elseif right:match("^Location:") then
            -- attach location to the previous event
            if last_event then
                last_event.location = right:match("^Location:%s*(.+)$") or ""
            end

        elseif left:match("^%d") and not left:match("%d+:%d+") then
            -- wrapped location continuation line (e.g. "1 Saarinen Cir...") — ignore

        elseif left ~= "" and not left:match("^%d") then
            -- date header line
            local date_str = parse_date_label(left)
            if date_str then
                current    = { header = date_str, events = {} }
                last_event = nil
                table.insert(days, current)
                if right ~= "" then
                    -- right may begin with a time: "9:00am   Event Title"
                    local t, title = right:match("^(%d+:%d+%a*)%s+(.*)")
                    last_event = {
                        text     = title and title:match("^%s*(.-)%s*$") or right,
                        time     = t or "",
                        length   = "",
                        location = "",
                    }
                    table.insert(current.events, last_event)
                end
            end
            -- non-date left-col text (e.g. wrapped location lines) → ignore

        else
            -- event line; right may begin with a time: "9:00am   Event Title"
            if current and right ~= "" then
                local t, title = right:match("^(%d+:%d+%a*)%s+(.*)")
                last_event = {
                    text     = title and title:match("^%s*(.-)%s*$") or right,
                    time     = t or "",
                    length   = "",
                    location = "",
                }
                table.insert(current.events, last_event)
            end
        end
    end
    return days
end

-- ── height calculation & prefetch ───────────────────────────────────────────

-- Mirrors the y-progression of conky_draw_gcal exactly.
local function compute_height(days)
    local y = Y_START
    for _, day in ipairs(days) do
        y = y + 6        -- divider gap
        y = y + HEADER_H -- date header
        for _, ev in ipairs(day.events) do
            y = y + LINE_H
            if ev.location ~= "" then
                y = y + LINE_H
            end
        end
        y = y + 4        -- post-group spacing
    end
    return y
end

-- Called from loadall.lua BEFORE conky_draw_bg so the bg height is known.
-- Fetches gcalcli output, parses it, caches the result, and returns the
-- required pixel height for sizing the background panel.
function gcal_prefetch()
    local raw     = run_gcalcli()
    _cache.days   = parse(raw)
    _cache.height = compute_height(_cache.days)
    return _cache.height
end

-- ── main draw ────────────────────────────────────────────────────────────────
function conky_draw_gcal()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- use pre-fetched cache when available (avoids a second gcalcli call)
    local days = _cache.days or parse(run_gcalcli())

    local y = Y_START

    for _, day in ipairs(days) do
        -- divider line above header
        draw_divider(cr, X, y, DIVIDER_W)
        y = y + 6

        -- date header
        set_color(cr, COLOR_HEADER)
        draw_text(cr, FONT_HEADER, SIZE_HEADER, true, X, y + SIZE_HEADER, day.header)
        y = y + HEADER_H

        -- events
        for _, ev in ipairs(day.events) do
            draw_bullet(cr, X + BULLET_OFFSET, y + SIZE_BODY / 2)

            set_color(cr, COLOR_EVENT)
            draw_text(cr, FONT_BODY, SIZE_BODY, false, X + EVENT_OFFSET, y + SIZE_BODY, ev.text)

            if ev.time ~= "" then
                set_color(cr, COLOR_TIME)
                draw_text(cr, FONT_BODY, SIZE_TIME, false, TIME_X, y + SIZE_BODY, ev.time)
            end

            if ev.length ~= "" then
                set_color(cr, COLOR_TIME)
                draw_text(cr, FONT_BODY, SIZE_TIME, false, LENGTH_X, y + SIZE_BODY, ev.length)
            end

            y = y + LINE_H

            if ev.location ~= "" then
                set_color(cr, COLOR_LOCATION)
                draw_text(cr, FONT_BODY, SIZE_LOCATION, false, X + EVENT_OFFSET, y + SIZE_LOCATION, ev.location)
                y = y + LINE_H
            end
        end

        y = y + 4  -- spacing after group
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
