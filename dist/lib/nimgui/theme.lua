-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

local color = require 'color'
local imgui = require 'mimgui'

local M = {}

M.DIRECTIONS = {
    instrument = { hue = 215, tint = 0.14, accentHue = 40, accentSat = 0.75, accentLight = 0.62 },
    dispatch   = { hue = 190, tint = 0.12, accentHue = 172, accentSat = 0.60, accentLight = 0.50 },
    garage     = { hue = 20,  tint = 0.07, accentHue = 355, accentSat = 0.70, accentLight = 0.58 },
    graphite   = { hue = 260, tint = 0.10, accentHue = 265, accentSat = 0.70, accentLight = 0.68 },
    paper      = { hue = 40,  tint = 0.15, accentHue = 215, accentSat = 0.70, accentLight = 0.42, mode = 'light' },
}

local SP = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }

local COLOR_STYLES = {
    'WindowBg', 'ChildBg', 'TitleBg', 'TitleBgActive', 'Border', 'Text', 'TextDisabled',
    'Button', 'ButtonHovered', 'ButtonActive', 'FrameBg', 'FrameBgHovered', 'FrameBgActive',
    'CheckMark', 'SliderGrab', 'Separator', 'Tab', 'TabActive', 'TabUnfocused',
    'Header', 'HeaderHovered', 'HeaderActive', 'PopupBg',
}

local COLOR_TOKENS = {
    WindowBg = 'bg', ChildBg = 'surface', TitleBg = 'bg', TitleBgActive = 'surface',
    Border = 'border', Text = 'text', TextDisabled = 'muted',
    Button = 'raised', ButtonHovered = 'raisedHover', ButtonActive = 'raisedActive',
    FrameBg = 'raised', FrameBgHovered = 'raisedHover', FrameBgActive = 'raisedActive',
    CheckMark = 'accent', SliderGrab = 'accent', Separator = 'border',
    Tab = 'raised', TabActive = 'accent', TabUnfocused = 'surface',
    Header = 'raised', HeaderHovered = 'raisedHover', HeaderActive = 'raisedActive',
    PopupBg = 'surface',
}

local VAR_STYLES = {
    'WindowRounding', 'ChildRounding', 'FrameRounding',
    'GrabRounding', 'ScrollbarRounding', 'TabRounding',
}
local VEC_STYLES = { 'WindowPadding', 'FramePadding', 'ItemSpacing' }

local stack = {}
local current = nil
local fallback = nil

function M.scale()
    local dpi = _G.MONET_DPI_SCALE
    if type(dpi) == 'number' and dpi > 0 then
        return dpi
    end
    local ok, _, height = pcall(_G.getScreenResolution)
    if ok and type(height) == 'number' and height > 0 then
        return math.min(2.0, math.max(1.0, height / 720))
    end
    return 1.0
end

function M.make(spec, opts)
    opts = opts or {}
    local direction = M.DIRECTIONS[spec] or spec
    if type(direction) ~= 'table' then
        error('nimgui.theme: unknown direction "' .. tostring(spec) .. '"', 2)
    end

    local scale = opts.scale or M.scale()
    local raw = color.palette(direction)
    local packed = {}
    for name, value in pairs(raw) do
        packed[name] = color.rgb(value)
    end
    packed.bg = color.rgb(raw.bg, opts.bg_alpha or 248)

    local theme = {
        mode = direction.mode or 'dark',
        scale = scale,
        radius = (opts.radius or 4) * scale,
        control_h = (opts.control_h or 44) * scale,
        raw = raw,
        color = packed,
        reduce_motion = opts.reduce_motion and true or false,
    }
    theme.sp = function(name)
        local value = SP[name]
        if value == nil then
            error('nimgui.theme: unknown spacing token "' .. tostring(name) .. '"', 2)
        end
        return value * scale
    end
    theme.push_colors = #COLOR_STYLES
    theme.push_vars = #VAR_STYLES + #VEC_STYLES
    return theme
end

function M.apply(spec, opts)
    local theme = M.make(spec, opts)
    current = theme
    return theme
end

function M.push(theme)
    if type(theme) ~= 'table' then
        error('nimgui.theme.push: theme must be a table', 2)
    end
    for i = 1, #COLOR_STYLES do
        local name = COLOR_STYLES[i]
        imgui.PushStyleColorU32(imgui.Col[name], theme.color[COLOR_TOKENS[name]])
    end
    for i = 1, #VAR_STYLES do
        imgui.PushStyleVarFloat(imgui.StyleVar[VAR_STYLES[i]], theme.radius)
    end
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(theme.sp('lg'), theme.sp('md')))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(theme.sp('sm'), theme.sp('sm')))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(theme.sp('sm'), theme.sp('sm')))
    stack[#stack + 1] = { colors = #COLOR_STYLES, vars = #VAR_STYLES + #VEC_STYLES, theme = theme }
    current = theme
    return theme
end

function M.pop()
    if #stack == 0 then
        return false, 'nimgui.theme.pop: no matching push'
    end
    local top = stack[#stack]
    stack[#stack] = nil
    imgui.PopStyleVar(top.vars)
    imgui.PopStyleColor(top.colors)
    current = stack[#stack] and stack[#stack].theme or nil
    return true
end

function M.pop_all()
    while #stack > 0 do
        M.pop()
    end
    current = nil
end

function M.depth()
    return #stack
end

function M.current()
    return current
end

function M.active()
    if current then
        return current
    end
    local scale = M.scale()
    if fallback == nil or fallback.scale ~= scale then
        fallback = M.make('graphite', { scale = scale })
    end
    return fallback
end

function M.reset()
    M.pop_all()
end

return M
