-- theme.lua - Shared color and theme definitions for alien conky suite
--
-- v1.1 2026-04-09 @rew62
local theme = {
    bg_color     = 0x1e1e2e,
    fg_color     = 0xcdd6f4,
    border_color = 0x89b4fa,
    border_width = 2,
    font         = "Sans 10",
    cairo_font   = "DejaVu Sans",
}

-- bgtab format:
-- {radius,x,y,w,h,color,alpha,draw,lwidth,outline_color,outline_alpha}
--theme.bgtab = '{10,0,0,0,0,0x000000,0.7,3,2,0x2E8B57,1.0}'
--theme.bgtab = '{10,0,0,0,0,0x000000,0.7,3,2,0x2E8B57,1.0}'


function theme.build_bgtab()
    return string.format(
        '{10,0,0,0,0,0x%06X,0.7,3,2,0x%06X,1.0}',
        theme.bg_color,
        theme.border_color
    )
end

theme.bgtab = theme.build_bgtab()






return theme
