-- Pure geometry: Hyprland reports physical monitor dimensions but logical
-- window sizes, reserved edges and monitor origins. Rotation swaps the axes.
return function(m, size, kind, toolbar)
    local width, height = m.width / m.scale, m.height / m.scale
    if m.transform % 2 == 1 then width, height = height, width end
    local r = m.reserved or {}
    local left, top = r.left or 0, r.top or 0
    local right, bottom = width - (r.right or 0), height - (r.bottom or 0)
    local gap = 8
    local x = (left + right - size.x) / 2
    local y = top + gap
    if kind == "preview" then
        x = right - size.x - gap
        -- On narrow/portrait screens the corner can overlap the toolbar.
        if toolbar and x < (left + right + toolbar.x) / 2 + gap then
            y = y + toolbar.y + gap
        end
    elseif kind == "toast" and toolbar then
        y = y + toolbar.y + gap
    end
    x = math.max(left, math.min(x, right - size.x))
    y = math.max(top, math.min(y, bottom - size.y))
    return math.floor(m.x + x), math.floor(m.y + y)
end
