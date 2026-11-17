-- color.lua
-- Palette helper for mimgui panels.
-- Colors are plain integers (0xRRGGBB); packed IM_COL32 (0xAABBGGRR) only through rgb().

local M = {}

function M.rgb(value, alpha)
    local r = math.floor(value / 0x10000) % 0x100
    local g = math.floor(value / 0x100) % 0x100
    local b = value % 0x100
    return (alpha or 255) * 0x1000000 + b * 0x10000 + g * 0x100 + r
end

function M.hsl(h, s, l)
    h = (h % 360) / 360
    local function channel(offset)
        local t = (h + offset) % 1
        local q = l < 0.5 and l * (1 + s) or l + s - l * s
        local p = 2 * l - q
        if t < 1 / 6 then return p + (q - p) * 6 * t end
        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end
    local function byte(x) return math.floor(x * 255 + 0.5) end
    return byte(channel(1 / 3)) * 0x10000 + byte(channel(0)) * 0x100 + byte(channel(-1 / 3))
end

local function linear(c)
    c = c / 255
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

function M.luminance(value)
    local r = math.floor(value / 0x10000) % 0x100
    local g = math.floor(value / 0x100) % 0x100
    local b = value % 0x100
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

function M.contrast(a, b)
    local la, lb = M.luminance(a), M.luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

function M.mix(a, b, t)
    local function channel(shift)
        local ca = math.floor(a / shift) % 0x100
        local cb = math.floor(b / shift) % 0x100
        return math.floor(ca + (cb - ca) * t + 0.5)
    end
    return channel(0x10000) * 0x10000 + channel(0x100) * 0x100 + channel(1)
end

local function fit(h, sat, light, background, min_ratio, step)
    local l = light
    while M.contrast(M.hsl(h, sat, l), background) < min_ratio and l > 0.02 and l < 0.98 do
        l = l + step
    end
    return M.hsl(h, sat, l)
end

function M.readable_on(background)
    local dark, light = M.hsl(0, 0, 0.06), M.hsl(0, 0, 0.97)
    return M.contrast(dark, background) >= M.contrast(light, background) and dark or light
end

function M.palette(spec)
    local dark = spec.mode ~= "light"
    local h, t = spec.hue, spec.tint
    local ladder = dark
        and { 0.05, 0.08, 0.115, 0.15, 0.19, 0.22 }
        or { 0.97, 0.94, 0.91, 0.88, 0.84, 0.80 }
    local step = dark and 0.01 or -0.01
    local p = {
        bg = M.hsl(h, t, ladder[1]),
        surface = M.hsl(h, t, ladder[2]),
        raised = M.hsl(h, t, ladder[3]),
        raisedHover = M.hsl(h, t, ladder[4]),
        raisedActive = M.hsl(h, t, ladder[5]),
        border = M.hsl(h, t, ladder[6]),
    }
    p.text = M.hsl(h, math.min(t, 0.2), dark and 0.93 or 0.10)
    p.muted = fit(h, math.min(t, 0.18), dark and 0.62 or 0.40, p.raised, 4.5, step)
    p.accent = fit(spec.accentHue, spec.accentSat, spec.accentLight, p.bg, 3, step)
    p.accentHover = M.hsl(spec.accentHue, spec.accentSat, spec.accentLight + (dark and 0.07 or -0.06))
    p.accentActive = M.hsl(spec.accentHue, spec.accentSat, spec.accentLight + (dark and -0.08 or 0.07))
    p.onAccent = M.readable_on(p.accent)
    p.success = fit(150, 0.45, 0.5, p.raised, 4.5, step)
    p.danger = fit(2, 0.62, 0.55, p.raised, 4.5, step)
    return p
end

return M
