-- background.lua - Background + border drawing
-- Adapted from @wim66 original; reads settings.lua for colors/dimensions
-- v1 02 2026-03-09 @rew62

require 'cairo'

local status, cairo_xlib = pcall(require, 'cairo_xlib')
if not status then
    cairo_xlib = setmetatable({}, {
        __index = function(_, key) return _G[key] end
    })
end

-- === Load settings.lua ===
local script_path = debug.getinfo(1, 'S').source:match[[^@?(.*[\/])[^\/]-$]]
local parent_path = script_path:gsub("scripts[\\/]$", "")
package.path = package.path .. ";" .. parent_path .. "?.lua"

local ok, err = pcall(function() require("settings") end)
if not ok then print("Error loading settings.lua: " .. err); return end
if not conky_vars then print("conky_vars not defined in settings.lua"); return end

conky_vars()

local unpack = table.unpack or unpack

-- ── color parsers (unchanged from original) ──────────────

local function parse_border_color(s)
    local g = {}
    for pos, col, a in s:gmatch("([%d%.]+),0x(%x+),([%d%.]+)") do
        g[#g+1] = {tonumber(pos), tonumber(col, 16), tonumber(a)}
    end
    if #g == 3 then return g end
    return {{0, 0x2E8B57, 1}, {0.5, 0x2E8B57, 1}, {1, 0x2E8B57, 1}}
end

local function parse_bg_color(s)
    local hex, a = s:match("0x(%x+),([%d%.]+)")
    if hex and a then return {{1, tonumber(hex, 16), tonumber(a)}} end
    return {{1, 0x000000, 0.5}}
end

local function parse_layer2_color(s)
    local g = {}
    for pos, col, a in s:gmatch("([%d%.]+),0x(%x+),([%d%.]+)") do
        g[#g+1] = {tonumber(pos), tonumber(col, 16), tonumber(a)}
    end
    if #g == 3 then return g end
    return {{0, 0x55007f, 0.5}, {0.5, 0xff69ff, 0.5}, {1, 0x55007f, 0.5}}
end

local border_color = parse_border_color(border_COLOR or "0,0x2E8B57,1,0.5,0x2E8B57,1,1,0x2E8B57,1")
local bg_color     = parse_bg_color(bg_COLOR         or "0x353376,0.4")
local layer2_color = parse_layer2_color(layer_2      or "0,0xffffff,0.5,0.5,0xc2c2c2,0.5,1,0xffffff,0.5")

-- ── box definitions ───────────────────────────────────────

local function get_boxes()
    --local W = width  or 340
    --local H = height or 300
    local W = conky_w or 300 
    local H = conky_h or 300
    return {
        {
            type = "background",
            x = 0, y = 0, w = W, h = H,
            centre_x = true,
            corners = {20, 20, 20, 20},
            rotation = 0,
            draw_me = true,
            colour = bg_color,
        },
        {
            type = "layer2",
            x = 0, y = 0, w = W, h = H,
            centre_x = true,
            corners = {20, 20, 20, 20},
            rotation = 0,
            draw_me = false,          -- enable if you want the gradient overlay
            linear_gradient = {W/2, 0, W/2, H},
            colours = layer2_color,
        },
        {
            type = "border",
            x = 0, y = 0, w = W + 2, h = H + 2,
            centre_x = true,
            corners = {20, 20, 20, 20},
            rotation = 0,
            draw_me = true,
            border = 2,
            colour = border_color,
            linear_gradient = {0, 0, 0, H},
        },
    }
end

-- ── geometry helpers ──────────────────────────────────────

local function hex_to_rgba(hex, alpha)
    return ((hex >> 16) & 0xFF) / 255,
           ((hex >>  8) & 0xFF) / 255,
           ( hex        & 0xFF) / 255,
           alpha
end

local function draw_rounded_rect(cr, x, y, w, h, r)
    local tl, tr, br, bl = unpack(r)
    cairo_new_path(cr)
    cairo_move_to(cr, x + tl, y)
    cairo_line_to(cr, x + w - tr, y)
    if tr > 0 then cairo_arc(cr, x+w-tr, y+tr,   tr,  -math.pi/2, 0)          else cairo_line_to(cr, x+w, y)   end
    cairo_line_to(cr, x+w, y+h-br)
    if br > 0 then cairo_arc(cr, x+w-br, y+h-br, br,   0,          math.pi/2)  else cairo_line_to(cr, x+w, y+h) end
    cairo_line_to(cr, x+bl, y+h)
    if bl > 0 then cairo_arc(cr, x+bl,   y+h-bl, bl,   math.pi/2,  math.pi)   else cairo_line_to(cr, x,   y+h) end
    cairo_line_to(cr, x, y+tl)
    if tl > 0 then cairo_arc(cr, x+tl,   y+tl,   tl,   math.pi,    3*math.pi/2) else cairo_line_to(cr, x, y) end
    cairo_close_path(cr)
end

local function centered_x(canvas_w, box_w)
    return (canvas_w - box_w) / 2
end

-- ── main draw function ────────────────────────────────────

function conky_draw_background()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- DEST_OVER: background paints behind what's already there
    cairo_set_operator(cr, CAIRO_OPERATOR_DEST_OVER)
    --cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    local cw = conky_window.width
    cairo_save(cr)

    for _, box in ipairs(get_boxes()) do
        if box.draw_me then
            local x, y, w, h = box.x, box.y, box.w, box.h
            if box.centre_x then x = centered_x(cw, w) end

            local cx    = x + w / 2
            local cy    = y + h / 2
            local angle = (box.rotation or 0) * math.pi / 180

            if box.type == "background" then
                cairo_save(cr)
                cairo_translate(cr, cx, cy)
                cairo_rotate(cr, angle)
                cairo_translate(cr, -cx, -cy)
                cairo_set_source_rgba(cr, hex_to_rgba(box.colour[1][2], box.colour[1][3]))
                draw_rounded_rect(cr, x, y, w, h, box.corners)
                cairo_fill(cr)
                cairo_restore(cr)

            elseif box.type == "layer2" then
                local grad = cairo_pattern_create_linear(unpack(box.linear_gradient))
                for _, c in ipairs(box.colours) do
                    cairo_pattern_add_color_stop_rgba(grad, c[1], hex_to_rgba(c[2], c[3]))
                end
                cairo_save(cr)
                cairo_translate(cr, cx, cy); cairo_rotate(cr, angle); cairo_translate(cr, -cx, -cy)
                cairo_set_source(cr, grad)
                draw_rounded_rect(cr, x, y, w, h, box.corners)
                cairo_fill(cr)
                cairo_restore(cr)
                cairo_pattern_destroy(grad)

            elseif box.type == "border" then
                local grad = cairo_pattern_create_linear(unpack(box.linear_gradient))
                for _, c in ipairs(box.colour) do
                    cairo_pattern_add_color_stop_rgba(grad, c[1], hex_to_rgba(c[2], c[3]))
                end
                cairo_save(cr)
                cairo_translate(cr, cx, cy); cairo_rotate(cr, angle); cairo_translate(cr, -cx, -cy)
                cairo_set_source(cr, grad)
                cairo_set_line_width(cr, box.border)
                local b2 = box.border / 2
                draw_rounded_rect(cr,
                    x + b2, y + b2, w - box.border, h - box.border,
                    {
                        math.max(0, box.corners[1] - b2),
                        math.max(0, box.corners[2] - b2),
                        math.max(0, box.corners[3] - b2),
                        math.max(0, box.corners[4] - b2),
                    })
                cairo_stroke(cr)
                cairo_restore(cr)
                cairo_pattern_destroy(grad)
            end
        end
    end

    cairo_restore(cr)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
