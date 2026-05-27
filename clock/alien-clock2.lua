-- c2.lua — standalone clock rings widget (conky -c c2.lua)
-- Lua functions first; conky.config/text guarded by `if conky` so this file
-- is also safe to load via lua_load without re-executing the config block.

-- During config parse the `conky` global exists; cairo bindings aren't
-- registered yet so we skip the require.  lua_load re-runs this file
-- with conky=nil, at which point cairo is available.
if not conky then require 'cairo' end

-- ── Configurable colors ──────────────────────────────────────────────────────
local ring_colour  = 0xD0B8E8   -- alien-dark purple (auzia colors.lua alien_dark.bg)
local ring_alpha   = 0.6
local clock_colour = 0x98FB98   -- pale green hands
local clock_alpha  = 0.9
-- ─────────────────────────────────────────────────────────────────────────────

local settings_table = {
  { name='time', arg='%S',    max=60, bg_colour=ring_colour, bg_alpha=0.1, fg_colour=ring_colour, fg_alpha=ring_alpha, x=160, y=82, radius=55, thickness=3,  start_angle=0, end_angle=360 },
  { name='time', arg='%M.%S', max=60, bg_colour=ring_colour, bg_alpha=0.1, fg_colour=ring_colour, fg_alpha=ring_alpha, x=160, y=82, radius=44, thickness=10, start_angle=0, end_angle=360 },
  { name='time', arg='%I.%M', max=12, bg_colour=ring_colour, bg_alpha=0.1, fg_colour=ring_colour, fg_alpha=ring_alpha, x=160, y=82, radius=34, thickness=3,  start_angle=0, end_angle=360 },
}

local clock_r = 50
local clock_x = 160
local clock_y = 82
local show_seconds = true

function rgb_to_r_g_b(colour, alpha)
  return ((colour / 0x10000) % 0x100) / 255.,
         ((colour / 0x100)   % 0x100) / 255.,
         (colour % 0x100)              / 255.,
         alpha
end

function draw_ring(cr, t, pt)
  local xc, yc       = pt['x'], pt['y']
  local ring_r, ring_w = pt['radius'], pt['thickness']
  local sa, ea        = pt['start_angle'], pt['end_angle']
  local bgc, bga      = pt['bg_colour'], pt['bg_alpha']
  local fgc, fga      = pt['fg_colour'], pt['fg_alpha']

  local angle_0 = sa * (2*math.pi/360) - math.pi/2
  local angle_f = ea * (2*math.pi/360) - math.pi/2
  local t_arc   = t * (angle_f - angle_0)

  cairo_arc(cr, xc, yc, ring_r, angle_0, angle_f)
  cairo_set_source_rgba(cr, rgb_to_r_g_b(bgc, bga))
  cairo_set_line_width(cr, ring_w)
  cairo_stroke(cr)

  cairo_arc(cr, xc, yc, ring_r, angle_0, angle_0 + t_arc)
  cairo_set_source_rgba(cr, rgb_to_r_g_b(fgc, fga))
  cairo_stroke(cr)
end

function draw_clock_hands(cr, xc, yc)
  local secs  = tonumber(os.date("%S"))
  local mins  = tonumber(os.date("%M"))
  local hours = tonumber(os.date("%I"))

  local secs_arc  = (2*math.pi/60) * secs
  local mins_arc  = (2*math.pi/60) * mins  + secs_arc/60
  local hours_arc = (2*math.pi/12) * hours + mins_arc/12

  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
  cairo_set_source_rgba(cr, rgb_to_r_g_b(clock_colour, clock_alpha))

  cairo_move_to(cr, xc, yc)
  cairo_line_to(cr, xc + 0.65*clock_r*math.sin(hours_arc), yc - 0.65*clock_r*math.cos(hours_arc))
  cairo_set_line_width(cr, 5)
  cairo_stroke(cr)

  cairo_move_to(cr, xc, yc)
  cairo_line_to(cr, xc + 0.95*clock_r*math.sin(mins_arc), yc - 0.95*clock_r*math.cos(mins_arc))
  cairo_set_line_width(cr, 3)
  cairo_stroke(cr)

  if show_seconds then
    cairo_move_to(cr, xc, yc)
    cairo_line_to(cr, xc + 1.1*clock_r*math.sin(secs_arc), yc - 1.1*clock_r*math.cos(secs_arc))
    cairo_set_line_width(cr, 1)
    cairo_stroke(cr)
  end
end

function conky_clock_rings()
  if conky_window == nil then return end

  local cs = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable,
    conky_window.visual,  conky_window.width, conky_window.height
  )
  local cr = cairo_create(cs)

  local update_num = tonumber(conky_parse('${updates}'))
  if update_num > 0 then
    for _, pt in ipairs(settings_table) do
      local value = 0

      if pt['arg'] == "%I.%M" then
        value = tonumber(os.date("%I")) + tonumber(os.date("%M"))/60
        if value > 12 then value = value - 12 end
      elseif pt['arg'] == "%M.%S" then
        value = tonumber(os.date("%M")) + tonumber(os.date("%S"))/60
      else
        local str = string.format('${%s %s}', pt['name'], pt['arg'])
        value = tonumber(conky_parse(str)) or 0
      end

      draw_ring(cr, value / pt['max'], pt)
    end
  end

  draw_clock_hands(cr, clock_x, clock_y)
end

-- When loaded via lua_load, conky global is nil — skip config/text.
if conky then
  conky.config = {
    background           = false,
    update_interval      = 1,
    cpu_avg_samples      = 1,
    net_avg_samples      = 2,
    override_utf8_locale = true,
    double_buffer        = true,
    no_buffers           = true,
    text_buffer_size     = 2048,
    imlib_cache_size     = 0,

    own_window             = true,
    own_window_type        = 'normal',
    own_window_argb_visual = true,
    own_window_argb_value  = 0,
    own_window_hints       = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_title       = 'c2',
    own_window_colour      = '#000000',

    xinerama_head       = 2,
    alignment           = 'ml',
    gap_x               = 0,
    gap_y               = 90,
    minimum_width       = 320, minimum_height = 170,
    maximum_width       = 320,
    border_inner_margin = 0,
    border_outer_margin = 0,

    draw_shades        = false,
    draw_outline       = false,
    draw_borders       = false,
    draw_graph_borders = false,

    use_xft       = true,
    font          = 'Ubuntu Mono:size=10',
    xftalpha      = 0.8,
    uppercase     = false,
    default_color = '#FFFFFF',

    lua_load          = './alien-clock2.lua',
    lua_draw_hook_pre = 'clock_rings',
  }

  conky.text = [[]]
end
