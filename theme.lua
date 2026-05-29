-- theme.lua - Shared color and theme definitions for alien conky suite
--
-- v1.1 2026-04-09 @rew62
local theme = {
    bg_color     = 0x1e1e2e,
    fg_color     = 0xcdd6f4,
    --border_color = 0x89b4fa,
    border_color = 0x98FB98,
    border_width = 2,
    --bg_alpha     = 0.7,
    --border_alpha = 1.0,
    bg_alpha     = 0.1,
    border_alpha = 1.0,
    font         = "Sans 10",
    cairo_font   = "DejaVuSansM Nerd Font Propo",
}

-- Simulated frosted glass - dark
--local theme = {
--    bg_color     = 0x1e1e2e,
--    fg_color     = 0xcdd6f4,
--    border_color = 0xcdd6f4,
--    border_width = 2,
--    bg_alpha     = 0.45,
--    border_alpha = 0.3,
--    font         = "Sans 10",
--    cairo_font   = "DejaVuSansM Nerd Font Propo",
--}

-- Simulated frosted glass - light
--local theme = {
--    bg_color     = 0xe0e8f0,
--    fg_color     = 0xcdd6f4,
--    border_color = 0xffffff,
--    border_width = 2,
--    bg_alpha     = 0.12,
--    border_alpha = 0.35,
--    font         = "Sans 10",
--    cairo_font   = "DejaVuSansM Nerd Font Propo",
--}

-- bgtab format:
-- {radius,x,y,w,h,color,alpha,draw,lwidth,outline_color,outline_alpha}
--theme.bgtab = '{10,0,0,0,0,0x000000,0.7,3,2,0x2E8B57,1.0}'
--theme.bgtab = '{10,0,0,0,0,0x000000,0.7,3,2,0x2E8B57,1.0}'


function theme.build_bgtab()
    return string.format(
        '{10,0,0,0,0,0x%06X,%.2f,3,2,0x%06X,%.2f}',
        theme.bg_color,
        theme.bg_alpha,
        theme.border_color,
        theme.border_alpha
    )
end

theme.bgtab = theme.build_bgtab()

return theme
