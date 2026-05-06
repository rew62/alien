-- aclock settings — edit these to customize the clock
-- v 1.0 2026-05-05 @rew62

local s = {}

-- Feature switches
s.MIN_TICK = true    -- show 60 minute tick marks and second hand
--s.MIN_TICK = false    -- show 60 minute tick marks and second hand

-- Canvas center and radius (match your conky width/height)
s.cx     = 100    -- center x
s.cy     = 100    -- center y
--s.radius = 88     -- outer ring radius
s.radius = 80     -- outer ring radius

-- Outer ring
s.ring_color = 0x89b4fa   -- blue 
s.ring_alpha = 1.0
s.ring_width = 3

-- Hour tick marks
s.tick_color       = 0xFFFFFF   -- white
s.tick_alpha       = 0.90
s.tick_major_len   = 14         -- 12, 3, 6, 9 positions
s.tick_major_width = 5
s.tick_minor_len   = 9
s.tick_minor_width = 3

-- Hour hand
s.hour_color      = 0xb8a8d0   -- purple
s.hour_alpha      = 1.0
s.hour_hand_pct   = 0.55       -- fraction of radius
s.hour_hand_width = 5

-- Minute hand
s.min_color      = 0x98fb98   -- alien green
s.min_alpha      = 1.0
s.min_hand_pct   = 0.80       -- fraction of radius
s.min_hand_width = 3

-- Minute tick marks (only used when MIN_TICK = true)
s.min_tick_color = 0xFFAA00   -- amber
s.min_tick_alpha = 0.60
s.min_tick_len   = 5
s.min_tick_width = 1.5

-- Second hand (only used when MIN_TICK = true)
s.sec_color      = 0xFFAA00   -- green
s.sec_alpha      = 1.0
s.sec_hand_pct   = 0.89       -- fraction of radius
s.sec_hand_width = 1.5

-- Alien glyph (rendered below center pivot)
s.glyph_char  = string.char(0xEE,0x8D,0xAE)  -- U+E36E
s.glyph_font  = "DejaVuSansM Nerd Font Propo"
s.glyph_size  = 24 
s.glyph_color = 0x98fb98   -- pale green
s.glyph_alpha = 1.0

-- Center pivot dot
s.center_color = 0x89B4FA
s.center_alpha = 1.0
s.center_r     = 5

return s
