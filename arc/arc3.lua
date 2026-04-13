-- arc3.lua - Horizon arc + weather panel + moon phase + sun/moon markers + planets
-- Extended arc.lua:
--   • 3-column weather panel moved up into the arc interior (y≈172-216),
--     above the arc endpoints, leaving the lower band free for moon phase.
--   • Moon phase restored at its original position (y≈252, near horizon).
--   • Separate OWM icon / temp text elements from the old layout are no longer
--     needed — the panel renders them directly.
--
-- Panel column order (left → right):
--   col1: weather icon (top)  + description (bottom)
--   col2: temp + unit (top)   + Feels XX° (bottom)
--   col3: humidity % (top)    + wind image + speed (bottom)
--
-- Data: owm_current.json, owm_parsed.txt, sky.vars, /dev/shm/owm_wind.png
-- Icons: /dev/shm/conky_icons/metno_*.png
-- v1.3 2026-04-11 @rew62  refactor: extract sub-drawing functions, remove dead code

local XDG       = os.getenv("XDG_CACHE_HOME") or "/dev/shm"
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or (XDG .. "/conky")

local CACHE_JSON   = CACHE_DIR .. "/owm_current.json"
local CACHE_PARSED = CACHE_DIR .. "/owm_parsed.txt"
local SKY_VARS     = CACHE_DIR .. "/sky.vars"

local ICON_DIR   = "/dev/shm/conky_icons/"
local WIND_PNG   = "/dev/shm/owm_wind.png"
local METNO_BASE = "https://cdn.jsdelivr.net/gh/metno/weathericons@main/weather/png/"

-- OWM icon code → Met.no symbol name
local OWM_TO_METNO = {
  ["01d"] = "clearsky_day",      ["01n"] = "clearsky_night",
  ["02d"] = "fair_day",          ["02n"] = "fair_night",
  ["03d"] = "partlycloudy_day",  ["03n"] = "partlycloudy_night",
  ["04d"] = "cloudy",            ["04n"] = "cloudy",
  ["09d"] = "lightrain",         ["09n"] = "lightrain",
  ["10d"] = "rain",              ["10n"] = "rain",
  ["11d"] = "thunder",           ["11n"] = "thunder",
  ["13d"] = "snow",              ["13n"] = "snow",
  ["50d"] = "fog",               ["50n"] = "fog",
}

-- =========================================================================
-- Widget configuration – edit to customize layout and style
-- =========================================================================
local CFG = {
  weather = {
    -- Arc center in conky window pixels
    center = { x = 285, y = 204 },

    -- Arc geometry: radius + span angles (screen degrees, y-up convention)
    arc    = { r = 170, start = 180, ["end"] = 0 },

    -- Horizontal reference line (sky horizon visual)
    hline  = { length = 460, width = 0.5, color = "89b4fa", dy = 58 },

    -- Arc stroke color (RGBA) for day vs night
    day_color   = { 0.65, 0.65, 0.65, 1.0 },
    night_color = { 0.14, 0.14, 0.14, 1.00 },

    -- Sunrise/sunset icon labels at arc ends
    sun_time_labels = {
      dy        = 44,
      lx_offset = 4,
      rx_offset = 0,
      icon_size = 28,
      time_size = 13,
      icon_dy   = 5,
    },

    -- Moon phase text: centered at arc base, above horizon line
    moon_phase = {
      sym_size  = 24,
      text_size = 11,
      dy        = -16,  -- px above horizon line (negative = upward)
      x_offset  = 0,
      text_dy   = -3,
    },
  },

  -- Cardinal direction labels (East / South|North / West)
  horizon_labels = {
    pt     = 12,
    color  = { 1, 1, 1, 1 },
    dy     = 24,    -- vertical offset for West and East labels
    dy_mid = 34,    -- independent vertical offset for South/North label
    lx     = 0,
    cx     = 0,
    rx     = 0,
  },

  -- Planet display
  planets = {
    clip  = true,
    style = {
      VENUS   = { r = 15, color = { 1.00, 0.95, 0.70, 1.00 } },
      MARS    = { r = 11, color = { 0.95, 0.45, 0.20, 1.00 } },
      JUPITER = { r = 14, color = { 0.90, 0.82, 0.65, 1.00 } },
      SATURN  = { r = 12, color = { 0.85, 0.75, 0.50, 1.00 } },
      MERCURY = { r =  9, color = { 0.78, 0.80, 0.86, 1.00 } },
    },
  },

  -- Sun / moon hollow-circle markers on the arc
  weather_markers = {
    sun  = { diameter = 36, stroke = 10.0, color = { 1.00, 0.78, 0.10, 1.00 } },
    moon = { diameter = 26, stroke = 10.0, color = { 0.75, 0.75, 0.80, 1.00 } },
  },

  -- -----------------------------------------------------------------------
  -- 3-column weather panel  (equal thirds, symmetric around arc cx=285)
  --
  -- Arc constraint at y_start=142:
  --   half_width = sqrt(170²-62²) ≈ 158.3 px  →  arc x = 127..443
  --   panel boundary x=127..443 is flush with arc; no content drawn there
  --   (leftmost drawn element: icon centered at cx1=177, spans x=156+)
  --
  -- Column layout  (col_w=100, col_gap=4, total=316 px):
  --   col1  x=127..227  cx=177
  --   div1  x=231
  --   col2  x=235..335  cx=285  ← exactly arc center
  --   div2  x=339
  --   col3  x=343..443  cx=393
  --
  -- Vertical:
  --   y_start=142  icon top
  --   y_row1 =170  first row baseline  (36pt cap-top lands at y≈136)
  --   y_row2 =200  second row baseline (30 px row separation)
  --   moon phase baseline y=252  →  ~27 px below panel text bottom
  -- -----------------------------------------------------------------------
  panel = {
    x_start  = 127,   -- left edge  (~8 px inside arc at y_start)
    x_end    = 443,   -- right edge (~8 px inside arc at y_start)
    y_start  = 142,   -- top of icon images
    y_row1   = 170,   -- first row text baselines  (temp, humidity)
    y_row2   = 200,   -- second row text baselines (feels-like, wind, desc)

    col1_w   = 100,   -- equal thirds: all three columns are 100 px
    col2_w   = 100,   -- col3 width derived from x_end, also resolves to 100

    col_gap  = 4,     -- px between column edge and divider centre

    icon_px  = 42,    -- weather icon display size (square px)
    wind_px  = 22,    -- wind arrow display size (square px)

    -- Font sizes (pt)
    sz_temp  = 64,
    sz_unit  = 18,
    sz_feels = 15,
    sz_desc  = 12,
    sz_meta  = 20,
    sz_wind  = 15,

    -- Colors
    col_temp  = { 1.00, 1.00, 1.00, 1.00 },
    col_unit  = { 0.75, 0.75, 0.75, 0.90 },
    col_feels = { 1.00, 0.65, 0.20, 0.90 },
    col_humid = { 0.95, 0.95, 0.95, 1.00 },
    col_desc  = { 0.80, 0.80, 0.80, 0.90 },
    col_wind  = { 0.85, 0.85, 0.85, 1.00 },
    col_div   = { 0.537, 0.706, 0.980, 1.0 },
  },
}

-- =========================================================================
-- Helpers
-- =========================================================================
local function file_exists(p)
  local f = io.open(p, "r"); if not f then return false end
  f:close(); return true
end

-- Read a single value from owm_current.json via jq
local function read_field(jq_path)
  if not file_exists(CACHE_JSON) then return nil end
  local cmd = string.format([[jq -r '%s // empty' %q 2>/dev/null]], jq_path, CACHE_JSON)
  local p = io.popen(cmd, "r"); if not p then return nil end
  local out = (p:read("*a") or ""):gsub("%s+$", "")
  p:close()
  return out ~= "" and out or nil
end

-- Read a field from owm_parsed.txt
local function read_parsed(field)
  local f = io.open(CACHE_PARSED, "r"); if not f then return nil end
  for line in f:lines() do
    local k, v = line:match("^(%w+)=(.+)$")
    if k == field then f:close(); return v end
  end
  f:close()
  return nil
end

-- Read the last occurrence of a numeric key from sky.vars
local function read_sky_num(key)
  local f = io.open(SKY_VARS, "r"); if not f then return nil end
  local val = nil
  for line in f:lines() do
    local v = line:match("^%s*" .. key .. "%s*=%s*([%-0-9%.]+)%s*$")
    if v then val = tonumber(v) end
  end
  f:close()
  return val
end

-- Fetch / cache a Met.no weather icon PNG; returns local path
local function fetch_metno_icon(name)
  local path = ICON_DIR .. "metno_" .. name .. ".png"
  if file_exists(path) then return path end
  os.execute(string.format('mkdir -p %q && curl -sfL "%s%s.png" -o %q &',
    ICON_DIR, METNO_BASE, name, path))
  local fallback = ICON_DIR .. "metno_clearsky_day.png"
  if file_exists(fallback) then return fallback end
  return path
end

-- Resolve icon: owm_parsed icon_metno → OWM icon code → default
local function get_icon_name()
  local nm = read_parsed("icon_metno")
  if nm and nm ~= "" then return nm end
  local code = read_field(".weather[0].icon")
  if code then return OWM_TO_METNO[code] or "partlycloudy_day" end
  return "partlycloudy_day"
end

-- Wind degrees → 8-point cardinal
local function deg_to_card(deg)
  if not deg then return "?" end
  local dirs = { "N","NE","E","SE","S","SW","W","NW" }
  return dirs[math.floor((deg + 22.5) / 45) % 8 + 1]
end

-- Moon phase symbol, name, illumination string, and hex color
local function moon_phase_data()
  local lp       = 2551443
  local now      = os.time()
  local new_moon = os.time{ year=2001, month=1, day=24, hour=13, min=46 }
  local phase    = ((now - new_moon) % lp) / lp
  local illum    = (1 - math.cos(phase * 2 * math.pi)) / 2 * 100

  local NEW      = "\u{E3D5}"
  local CRES     = { "\u{E38E}", "\u{E38F}", "\u{E390}", "\u{E391}", "\u{E392}", "\u{E393}" }
  local FIRST    = "\u{E394}"
  local GIB      = { "\u{E395}", "\u{E396}", "\u{E397}", "\u{E398}", "\u{E399}", "\u{E39A}" }
  local FULL     = "\u{E39B}"
  local WAN_GIB  = { "\u{E39C}", "\u{E39D}", "\u{E39E}", "\u{E39F}", "\u{E3A0}", "\u{E3A1}" }
  local LAST     = "\u{E3A2}"
  local WAN_CRES = { "\u{E3A3}", "\u{E3A4}", "\u{E3A5}", "\u{E3A6}", "\u{E3A7}", "\u{E3A8}" }

  local sym, name, col

  if phase < 0.02 or phase >= 0.98 then
    sym, name, col = NEW, "New Moon", "546E7A"
  elseif phase < 0.23 then
    local i = math.min(math.floor((phase - 0.02) / 0.21 * 6) + 1, 6)
    sym, name, col = CRES[i], "Waxing Crescent", "B0BEC5"
  elseif phase < 0.27 then
    sym, name, col = FIRST, "First Quarter", "81D4FA"
  elseif phase < 0.48 then
    local i = math.min(math.floor((phase - 0.27) / 0.21 * 6) + 1, 6)
    sym, name, col = GIB[i], "Waxing Gibbous", "E0E0E0"
  elseif phase < 0.52 then
    sym, name, col = FULL, "Full Moon", "FFF59D"
  elseif phase < 0.73 then
    local i = math.min(math.floor((phase - 0.52) / 0.21 * 6) + 1, 6)
    sym, name, col = WAN_GIB[i], "Waning Gibbous", "E0E0E0"
  elseif phase < 0.77 then
    sym, name, col = LAST, "Last Quarter", "81D4FA"
  else
    local i = math.min(math.floor((phase - 0.77) / 0.21 * 6) + 1, 6)
    sym, name, col = WAN_CRES[i], "Waning Crescent", "B0BEC5"
  end

  return sym, name, string.format("(%.1f%%)", illum), col
end

-- Arc geometry from CFG
local function get_arc_geometry()
  local c = CFG.weather.center
  local a = CFG.weather.arc
  return c.x, c.y, a.r, a.start, a["end"]
end

local function deg2rad(d)   return (math.pi / 180) * d end
local function clamp01(x)   return x < 0 and 0 or (x > 1 and 1 or x) end

local function pt_on_arc(cx, cy, r, ang_deg)
  local th = deg2rad(ang_deg)
  return cx + r * math.cos(th), cy - r * math.sin(th)
end

local function norm_deg(d)
  d = d % 360; if d < 0 then d = d + 360 end; return d
end

local function on_visible_arc(theta_deg, sdeg, edeg)
  local t = norm_deg(theta_deg)
  local s, e = norm_deg(sdeg), norm_deg(edeg)
  if s < e then s, e = e, s end
  return t >= e and t <= s
end

local function arc_span(start_deg, end_deg)
  local s = (start_deg - end_deg) % 360
  return s == 0 and 360 or s
end

local function hex_to_rgba(hex, a)
  hex = (hex or "A0A0A0"):gsub("#", "")
  return tonumber(hex:sub(1,2),16)/255,
         tonumber(hex:sub(3,4),16)/255,
         tonumber(hex:sub(5,6),16)/255,
         (a == nil and 1 or a)
end

-- Draw a PNG image scaled to w×h at screen position (x, y)
local function draw_image(cr, path, x, y, w, h)
  local surf = cairo_image_surface_create_from_png(path)
  if cairo_surface_status(surf) ~= 0 then cairo_surface_destroy(surf); return end
  local iw = cairo_image_surface_get_width(surf)
  local ih = cairo_image_surface_get_height(surf)
  if iw == 0 or ih == 0 then cairo_surface_destroy(surf); return end
  cairo_save(cr)
  cairo_translate(cr, x, y)
  cairo_scale(cr, w / iw, h / ih)
  cairo_set_source_surface(cr, surf, 0, 0)
  cairo_paint(cr)
  cairo_restore(cr)
  cairo_surface_destroy(surf)
end

-- =========================================================================
-- Public API: ${lua_parse owm <key>}
-- =========================================================================
function conky_owm(key)
  if not key or key == "" then return "" end
  if key == "city"         then return read_field(".name") or "" end
  if key == "desc"         then return read_field(".weather[0].description") or "" end
  if key == "temp"         then
    local t = tonumber(read_field(".main.temp") or "")
    return t and string.format("%.0f", t) or ""
  end
  if key == "humidity"     then return read_field(".main.humidity") or "" end
  if key == "temp_unit"    then return read_parsed("temp_unit") or "°F" end
  if key == "sunrise"      then return read_parsed("sunrise") or "" end
  if key == "sunset"       then return read_parsed("sunset")  or "" end
  if key == "draw_horizon" then return conky_owm_draw_horizon() or "" end
  if key == "sun_labels"   then return conky_owm_sun_labels()   or "" end
  return ""
end

local has_cairo = pcall(require, "cairo")

-- =========================================================================
-- Sub-drawing functions (called from conky_owm_draw_horizon)
-- =========================================================================

local function draw_arc_stroke(cr, cx, cy, r, ARC_START, ARC_END)
  cairo_save(cr)
  cairo_set_line_width(cr, 1.5)
  local sr_ts    = tonumber(read_field(".sys.sunrise") or "")
  local ss_ts    = tonumber(read_field(".sys.sunset")  or "")
  local now      = os.time()
  local is_night = sr_ts and ss_ts and (now < sr_ts or now > ss_ts)
  local col      = is_night and CFG.weather.night_color or CFG.weather.day_color
  cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4])
  cairo_arc(cr, cx, cy, r, deg2rad(ARC_START), deg2rad(ARC_END))
  cairo_stroke(cr)
  cairo_new_path(cr)
  cairo_restore(cr)
end

local function draw_horizon_line(cr, cx, cy)
  local H = CFG.weather.hline
  local r_, g_, b_, a_ = hex_to_rgba(H.color, 1.0)
  cairo_set_source_rgba(cr, r_, g_, b_, a_)
  cairo_set_line_width(cr, H.width)
  cairo_move_to(cr, cx - H.length/2, cy + H.dy)
  cairo_line_to(cr, cx + H.length/2, cy + H.dy)
  cairo_stroke(cr)
end

local function draw_cardinal_labels(cr, cx, cy, r, ARC_START, ARC_END)
  local HL = CFG.horizon_labels
  local function arc_mid(s, e)
    local span = (s - e) % 360
    return (e + (span == 0 and 360 or span) / 2) % 360
  end
  local lat  = tonumber(read_field(".coord.lat"))
  local apex = (lat and lat < 0) and "North" or "South"
  local lx, ly = pt_on_arc(cx, cy, r, ARC_START)
  local rx, ry = pt_on_arc(cx, cy, r, ARC_END)
  local mx, my = pt_on_arc(cx, cy, r, arc_mid(ARC_START, ARC_END))
  ly, ry, my = ly + HL.dy, ry + HL.dy, my + (HL.dy_mid or HL.dy)
  lx, rx, mx = lx + HL.lx, rx + HL.rx, mx + HL.cx
  cairo_save(cr)
  cairo_new_path(cr)
  cairo_select_font_face(cr, "Sans", 0, 0)
  cairo_set_font_size(cr, HL.pt)
  cairo_set_source_rgba(cr, HL.color[1], HL.color[2], HL.color[3], HL.color[4])
  local ext = cairo_text_extents_t:create()
  for _, lbl in ipairs({ {"West", lx, ly}, {apex, mx, my}, {"East", rx, ry} }) do
    cairo_text_extents(cr, lbl[1], ext)
    cairo_move_to(cr, lbl[2] - ext.width/2, lbl[3])
    cairo_text_path(cr, lbl[1])
    cairo_fill(cr)
  end
  cairo_new_path(cr)
  cairo_restore(cr)
end

local function draw_sun_marker(cr, cx, cy, r, ARC_START, ARC_END)
  cairo_save(cr)
  local sr_ts = tonumber(read_field(".sys.sunrise") or "")
  local ss_ts = tonumber(read_field(".sys.sunset")  or "")
  local now   = os.time()
  if sr_ts and ss_ts and now >= sr_ts and now <= ss_ts then
    local p     = clamp01((now - sr_ts) / (ss_ts - sr_ts))
    local span  = arc_span(ARC_START, ARC_END)
    local theta = (ARC_END + p * span) % 360
    local sx, sy = pt_on_arc(cx, cy, r, theta)
    local S = CFG.weather_markers.sun
    cairo_set_line_width(cr, S.stroke)
    cairo_set_source_rgba(cr, S.color[1], S.color[2], S.color[3], S.color[4])
    cairo_arc(cr, sx, sy, S.diameter/2, 0, 2*math.pi)
    cairo_stroke(cr)
    cairo_new_path(cr)
  end
  cairo_restore(cr)
end

local function draw_moon_marker(cr, cx, cy, r, ARC_START, ARC_END)
  cairo_save(cr)
  -- Use azimuth-based MOON_THETA (same approach as planets) for accurate
  -- position. MOON_THETA is only written by sky_update.py when ALT > 0,
  -- so its presence implicitly gates drawing to when the moon is up.
  local theta = read_sky_num("MOON_THETA")
  if theta and on_visible_arc(theta, ARC_START, ARC_END) then
    local mx, my = pt_on_arc(cx, cy, r, theta)
    local M = CFG.weather_markers.moon
    cairo_set_line_width(cr, M.stroke)
    cairo_set_source_rgba(cr, M.color[1], M.color[2], M.color[3], M.color[4])
    cairo_arc(cr, mx, my, M.diameter/2, 0, 2*math.pi)
    cairo_stroke(cr)
    cairo_new_path(cr)
  end
  -- [old: time-based interpolation — inaccurate when moon rises/sets off E/W]
  -- local rise_ts = read_sky_num("MOON_RISE_TS")
  -- local set_ts  = read_sky_num("MOON_SET_TS")
  -- if rise_ts and set_ts then
  --   local now = os.time()
  --   if now >= rise_ts and now <= set_ts then
  --     local p     = clamp01((now - rise_ts) / math.max(1, set_ts - rise_ts))
  --     local span  = arc_span(ARC_START, ARC_END)
  --     local theta = (ARC_END + p * span) % 360
  --     local mx, my = pt_on_arc(cx, cy, r, theta)
  --     local M = CFG.weather_markers.moon
  --     cairo_set_line_width(cr, M.stroke)
  --     cairo_set_source_rgba(cr, M.color[1], M.color[2], M.color[3], M.color[4])
  --     cairo_arc(cr, mx, my, M.diameter/2, 0, 2*math.pi)
  --     cairo_stroke(cr)
  --     cairo_new_path(cr)
  --   end
  -- end
  cairo_restore(cr)
end

local function draw_planets(cr, cx, cy, r, ARC_START, ARC_END)
  local clip   = CFG.planets.clip
  local styles = CFG.planets.style

  local function theta_for(prefix)
    local t = read_sky_num(prefix .. "_THETA")
    if t ~= nil then return t end
    local az = read_sky_num(prefix .. "_AZ")
    if az == nil then return nil end
    az = (az % 360 + 360) % 360
    if not (az > 90 and az < 270) then return nil end
    local p    = (az - 90) / 180.0
    local span = arc_span(ARC_START, ARC_END)
    return (ARC_END + p * span) % 360
  end

  for _, name in ipairs({"VENUS","MARS","JUPITER","SATURN","MERCURY"}) do
    local theta = theta_for(name)
    local style = styles[name]
    if theta and not (clip and not on_visible_arc(theta, ARC_START, ARC_END)) then
      local px, py = pt_on_arc(cx, cy, r, theta)
      local c = style.color
      cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
      cairo_arc(cr, px, py, style.r, 0, 2*math.pi)
      cairo_fill(cr)
    end
  end
end

local function draw_moon_phase(cr, cx, cy)
  cairo_save(cr)
  cairo_new_path(cr)
  local sym, moon_name, moon_pct, col_hex = moon_phase_data()
  local MP       = CFG.weather.moon_phase
  local NFNT     = "MonaspiceNe Nerd Font Mono"
  local moon_y   = cy + CFG.weather.hline.dy + MP.dy
  local name_str = moon_name .. "  "
  local ext = cairo_text_extents_t:create()

  cairo_select_font_face(cr, NFNT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, MP.sym_size)
  cairo_text_extents(cr, sym, ext)
  local sym_w = ext.x_advance

  cairo_set_font_size(cr, MP.text_size)
  cairo_text_extents(cr, "  ", ext)
  local gap_w = ext.x_advance
  cairo_text_extents(cr, name_str, ext)
  local name_w = ext.x_advance
  cairo_text_extents(cr, moon_pct, ext)
  local pct_w = ext.x_advance

  local start_x = cx - (sym_w + gap_w + name_w + pct_w) / 2 + MP.x_offset
  local sr, sg, sb = hex_to_rgba(col_hex, 1.0)

  cairo_set_font_size(cr, MP.sym_size)
  cairo_set_source_rgba(cr, sr, sg, sb, 1.0)
  cairo_move_to(cr, start_x, moon_y)
  cairo_show_text(cr, sym)

  cairo_set_font_size(cr, MP.text_size)
  cairo_set_source_rgba(cr, 0x90/255, 0xA4/255, 0xAE/255, 1.0)
  cairo_move_to(cr, start_x + sym_w + gap_w, moon_y + MP.text_dy)
  cairo_show_text(cr, name_str)

  cairo_set_source_rgba(cr, 0x4D/255, 0xD0/255, 0xE1/255, 1.0)
  cairo_move_to(cr, start_x + sym_w + gap_w + name_w, moon_y + MP.text_dy)
  cairo_show_text(cr, moon_pct)

  cairo_new_path(cr)
  cairo_restore(cr)
end

-- =========================================================================
-- Weather panel: 3-column block in the upper arc interior
-- =========================================================================
local function draw_weather_panel(cr)
  local P = CFG.panel

  local icon_path = fetch_metno_icon(get_icon_name())

  local temp_n    = tonumber(read_field(".main.temp")       or "")
  local feels_n   = tonumber(read_field(".main.feels_like") or "")
  local humidity  = read_field(".main.humidity")            or "--"
  local wind_spd  = tonumber(read_field(".wind.speed")      or "")
  local wind_deg  = tonumber(read_field(".wind.deg")        or "")
  local desc      = read_field(".weather[0].description")   or ""
  local temp_unit = read_parsed("temp_unit")                or "°F"
  local wind_unit = read_parsed("wind_unit")                or "mph"

  local temp_str  = temp_n  and string.format("%.0f", temp_n)  or "--"
  local feels_str = feels_n and string.format("%.0f", feels_n) or "--"
  local wspd_str  = wind_spd and string.format("%.0f", wind_spd) or "--"

  if #desc > 0 then desc = desc:sub(1,1):upper() .. desc:sub(2) end

  local x1    = P.x_start
  local div1  = x1   + P.col1_w + P.col_gap
  local x2    = div1 + P.col_gap
  local div2  = x2   + P.col2_w + P.col_gap
  local x3    = div2 + P.col_gap
  local col3_w = P.x_end - x3

  local cx1 = x1 + P.col1_w  / 2
  local cx2 = x2 + P.col2_w  / 2
  local cx3 = x3 + col3_w    / 2

  local y0     = P.y_start
  local y1     = P.y_row1
  local y2     = P.y_row2
  local div_y2 = y2 + 4

  local FONT = "Sans"
  local ext  = cairo_text_extents_t:create()

  -- Inline helpers ----------------------------------------------------------
  local function rgba(c) cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4]) end

  local function measure(text, size, bold)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
      bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    cairo_text_extents(cr, text, ext)
    return ext.x_advance
  end

  local function draw_c(text, cx_pos, y_pos, size, col, bold)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
      bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    rgba(col)
    cairo_text_extents(cr, text, ext)
    cairo_move_to(cr, cx_pos - (ext.width / 2 + ext.x_bearing), y_pos)
    cairo_show_text(cr, text)
  end

  local function divider(x_pos)
    rgba(P.col_div)
    cairo_set_line_width(cr, 1.5)
    cairo_move_to(cr, math.floor(x_pos) + 0.5, y0 + 10)
    cairo_line_to(cr, math.floor(x_pos) + 0.5, div_y2)
    cairo_stroke(cr)
  end
  --------------------------------------------------------------------------

  cairo_save(cr)
  cairo_new_path(cr)

  -- Col 1: icon (top) + description (bottom)
  draw_image(cr, icon_path, cx1 - P.icon_px / 2, y0, P.icon_px, P.icon_px)
  draw_c(desc, cx1, y2, P.sz_desc, P.col_desc, false)

  divider(div1)

  -- Col 2: temp + unit (top) / feels-like (bottom)
  local tw = measure(temp_str,  P.sz_temp, true)
  local uw = measure(temp_unit, P.sz_unit, false)
  local pair_x = cx2 - (tw + 2 + uw) / 2 + 8

  cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
  cairo_set_font_size(cr, P.sz_temp)
  rgba(P.col_temp)
  cairo_move_to(cr, pair_x, y1)
  cairo_show_text(cr, temp_str)

  -- Unit raised to approximate superscript (half the size-difference)
  cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, P.sz_unit)
  rgba(P.col_unit)
  local unit_raise = math.floor((P.sz_temp - P.sz_unit) * 0.45)
  cairo_move_to(cr, pair_x + tw + 4, y1 - unit_raise - 10)
  cairo_show_text(cr, temp_unit)

  draw_c("Feels " .. feels_str .. temp_unit, cx2, y2, P.sz_feels, P.col_feels, false)

  divider(div2)

  -- Col 3: humidity % (top) / wind image + speed (bottom)
  draw_c(humidity .. "%", cx3, y1, P.sz_meta, P.col_humid, false)

  local wind_main   = deg_to_card(wind_deg) .. "  " .. wspd_str .. " "
  local has_wind    = file_exists(WIND_PNG)
  local img_w       = has_wind and P.wind_px or 0
  local img_gap     = 6      -- px between arrow right edge and cardinal text
  local arrow_nudge = 4      -- px to shift arrow right within the group
  local wmw         = measure(wind_main,  P.sz_wind,     false)
  local wuw         = measure(wind_unit,  P.sz_wind - 4, false)
  local group_w     = img_w + arrow_nudge + img_gap + wmw + wuw
  local gx          = cx3 - group_w / 2

  if has_wind then
    draw_image(cr, WIND_PNG, gx + arrow_nudge, y2 - P.wind_px + 6, P.wind_px, P.wind_px)
  end

  cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, P.sz_wind)
  rgba(P.col_wind)
  cairo_move_to(cr, gx + img_w + arrow_nudge + img_gap, y2)
  cairo_show_text(cr, wind_main)

  cairo_set_font_size(cr, P.sz_wind - 4)
  cairo_move_to(cr, gx + img_w + arrow_nudge + img_gap + wmw, y2)
  cairo_show_text(cr, wind_unit)

  cairo_new_path(cr)
  cairo_restore(cr)
end

-- =========================================================================
-- Draw: horizon arc + cardinal labels + sun + moon + planets
--       + weather panel (upper interior) + moon phase (lower interior)
-- lua_draw_hook_pre = 'owm_draw_horizon'  →  conky_owm_draw_horizon()
-- =========================================================================
function conky_owm_draw_horizon()
  if not has_cairo or not conky_window then return "" end

  local cs = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable,
    conky_window.visual, conky_window.width, conky_window.height)
  local cr = cairo_create(cs)
  cairo_save(cr)
  cairo_new_path(cr)

  local cx, cy, r, ARC_START, ARC_END = get_arc_geometry()

  draw_arc_stroke      (cr, cx, cy, r, ARC_START, ARC_END)
  draw_horizon_line    (cr, cx, cy)
  draw_cardinal_labels (cr, cx, cy, r, ARC_START, ARC_END)
  draw_sun_marker      (cr, cx, cy, r, ARC_START, ARC_END)
  draw_moon_marker     (cr, cx, cy, r, ARC_START, ARC_END)
  draw_planets         (cr, cx, cy, r, ARC_START, ARC_END)
  draw_weather_panel   (cr)
  draw_moon_phase      (cr, cx, cy)

  cairo_restore(cr)
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
  return ""
end

-- =========================================================================
-- Draw: sunrise/sunset icon labels at arc ends
-- East end (right): 󰖜 icon + time  ← sunrise always rises in east
-- West end (left):  time + 󰖛 icon  ← sunset always sets in west
-- =========================================================================
function conky_owm_sun_labels()
  if not has_cairo or not conky_window then return "" end

  local cs = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable,
    conky_window.visual, conky_window.width, conky_window.height)
  local cr = cairo_create(cs)
  cairo_save(cr)

  local cx, cy, r, ARC_START, ARC_END = get_arc_geometry()
  local lx, ly = pt_on_arc(cx, cy, r, ARC_START)   -- West end → sunset
  local rx, ry = pt_on_arc(cx, cy, r, ARC_END)     -- East end → sunrise

  local L = CFG.weather.sun_time_labels
  ly, ry = ly + L.dy, ry + L.dy
  lx, rx = lx + L.lx_offset, rx + L.rx_offset

  local sunrise = read_parsed("sunrise") or "--:--"
  local sunset  = read_parsed("sunset")  or "--:--"

  local NFNT = "MonaspiceNe Nerd Font Mono"

  local sr_icon_r, sr_icon_g, sr_icon_b = hex_to_rgba("FFB74D", 1.0)
  local sr_time_r, sr_time_g, sr_time_b = hex_to_rgba("FFECB3", 1.0)
  local ss_time_r, ss_time_g, ss_time_b = hex_to_rgba("FFAB91", 1.0)
  local ss_icon_r, ss_icon_g, ss_icon_b = hex_to_rgba("FF7043", 1.0)

  local ext = cairo_text_extents_t:create()

  local function draw_label(anchor_x, y, segs)
    cairo_select_font_face(cr, NFNT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    local widths = {}
    local total  = 0
    for i, seg in ipairs(segs) do
      cairo_set_font_size(cr, seg[2])
      cairo_text_extents(cr, seg[1], ext)
      widths[i] = ext.x_advance
      total = total + widths[i]
    end
    local x = anchor_x - total / 2
    for i, seg in ipairs(segs) do
      cairo_set_font_size(cr, seg[2])
      cairo_set_source_rgba(cr, seg[3], seg[4], seg[5], 1.0)
      cairo_move_to(cr, x + (seg[7] or 0), y + (seg[6] or 0))
      cairo_show_text(cr, seg[1])
      x = x + widths[i]
    end
  end

  draw_label(rx, ry, {
    { "󰖜 ", L.icon_size, sr_icon_r, sr_icon_g, sr_icon_b, L.icon_dy, 0 },
    { sunrise, L.time_size, sr_time_r, sr_time_g, sr_time_b, 0, -6 },
  })

  draw_label(lx, ly, {
    { sunset .. " ", L.time_size, ss_time_r, ss_time_g, ss_time_b, 0 },
    { "󰖛",          L.icon_size, ss_icon_r, ss_icon_g, ss_icon_b, L.icon_dy },
  })

  cairo_new_path(cr)
  cairo_restore(cr)
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
  return ""
end
