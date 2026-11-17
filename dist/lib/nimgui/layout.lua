-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

local imgui = require 'mimgui'
local theme = require 'nimgui.theme'

local M = {}

local panels = {}
local child_depth = 0

local function vec2(value, name)
    if type(value) == 'cdata' then
        return value
    end
    if type(value) ~= 'table' then
        error('nimgui.layout: ' .. name .. ' must be a table or ImVec2', 3)
    end
    local x = value[1]
    local y = value[2]
    if x == nil then x = value.x end
    if y == nil then y = value.y end
    if type(x) ~= 'number' or type(y) ~= 'number' then
        error('nimgui.layout: ' .. name .. ' needs numeric x and y', 3)
    end
    return imgui.ImVec2(x, y)
end

function M.begin_panel(id, opts)
    if type(id) ~= 'string' or id == '' then
        error('nimgui.layout.begin_panel: id must be a non-empty string', 2)
    end
    opts = opts or {}

    local pushed_theme = false
    if opts.theme then
        theme.push(opts.theme)
        pushed_theme = true
    elseif theme.current() == nil then
        theme.push(theme.active())
        pushed_theme = true
    end

    if opts.pos then
        imgui.SetNextWindowPos(
            vec2(opts.pos, 'pos'),
            opts.anchored and imgui.Cond.Always or imgui.Cond.FirstUseEver,
            opts.pivot and vec2(opts.pivot, 'pivot') or imgui.ImVec2(0, 0))
    end
    if opts.size then
        local size_cond = opts.size_cond
            or (opts.anchored and imgui.Cond.Always or imgui.Cond.FirstUseEver)
        imgui.SetNextWindowSize(vec2(opts.size, 'size'), size_cond)
    end
    if opts.min or opts.max then
        local min = opts.min and vec2(opts.min, 'min') or imgui.ImVec2(0, 0)
        local max = opts.max and vec2(opts.max, 'max') or imgui.ImVec2(3.402823e38, 3.402823e38)
        imgui.SetNextWindowSizeConstraints(min, max)
    end

    local pushed_alpha = false
    if type(opts.alpha) == 'number' and opts.alpha < 1 then
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, opts.alpha)
        pushed_alpha = true
    end

    local visible = imgui.Begin(id, opts.open, opts.flags or 0)
    panels[#panels + 1] = { theme = pushed_theme, alpha = pushed_alpha }
    return visible
end

function M.end_panel()
    local index = #panels
    if index == 0 then
        return false, 'nimgui.layout.end_panel: no matching begin_panel'
    end
    local panel = panels[index]
    panels[index] = nil
    imgui.End()
    if panel.alpha then
        imgui.PopStyleVar(1)
    end
    if panel.theme then
        theme.pop()
    end
    return true
end

function M.begin_child(id, size, border)
    if type(id) ~= 'string' or id == '' then
        error('nimgui.layout.begin_child: id must be a non-empty string', 2)
    end
    local visible = imgui.BeginChild(
        id,
        size and vec2(size, 'size') or imgui.ImVec2(0, 0),
        border and true or false)
    child_depth = child_depth + 1
    return visible
end

function M.end_child()
    if child_depth == 0 then
        return false, 'nimgui.layout.end_child: no matching begin_child'
    end
    child_depth = child_depth - 1
    imgui.EndChild()
    return true
end

function M.spacer(size)
    local value = size or theme.active().sp('md')
    if type(value) ~= 'number' then
        error('nimgui.layout.spacer: size must be a number', 2)
    end
    imgui.Dummy(imgui.ImVec2(0, value))
end

function M.same_line(offset)
    imgui.SameLine(offset or 0)
end

function M.separator()
    imgui.Separator()
end

function M.grid_columns(avail_x, cell_w, gap)
    if type(avail_x) ~= 'number' or type(cell_w) ~= 'number' or cell_w <= 0 then
        error('nimgui.layout.grid_columns: avail_x and cell_w must be positive numbers', 2)
    end
    gap = gap or 8
    return math.max(1, math.floor((avail_x + gap) / (cell_w + gap)))
end

local function utf8_boundary(text, index)
    while index > 0 do
        local byte = text:byte(index + 1)
        if not byte or byte < 0x80 or byte >= 0xC0 then
            return index
        end
        index = index - 1
    end
    return 0
end

function M.truncate(text, max_width)
    text = tostring(text)
    if type(max_width) ~= 'number' or max_width <= 0 then
        return text
    end
    if imgui.CalcTextSize(text).x <= max_width then
        return text
    end
    local cut = #text
    while cut > 0 do
        cut = utf8_boundary(text, cut)
        if cut == 0 then
            break
        end
        local candidate = text:sub(1, cut) .. '...'
        if imgui.CalcTextSize(candidate).x <= max_width then
            return candidate
        end
        cut = cut - 1
    end
    return '...'
end

function M.footer_height()
    local t = theme.active()
    return t.control_h + t.sp('md')
end

function M.depth()
    return #panels, child_depth
end

function M.reset()
    while child_depth > 0 do
        child_depth = child_depth - 1
        imgui.EndChild()
    end
    while #panels > 0 do
        M.end_panel()
    end
end

return M
