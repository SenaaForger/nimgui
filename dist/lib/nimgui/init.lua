-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

local imgui = require 'mimgui'
local theme = require 'nimgui.theme'
local state = require 'nimgui.state'
local layout = require 'nimgui.layout'
local widgets = require 'nimgui.widgets'
local media = require 'nimgui.media'
local fonts = require 'nimgui.fonts'

local M = {}
M._VERSION = '0.1.0'

local function has(name)
    local ok, value = pcall(function() return imgui[name] end)
    return ok and value ~= nil
end

local function has_global(name)
    local ok, value = pcall(function() return _G[name] end)
    return ok and value ~= nil
end

local function has_new(kind)
    local ok, value = pcall(function() return imgui.new[kind] end)
    return ok and value ~= nil
end

local capabilities = nil

local function build_capabilities()
    local caps = {}
    caps.draw_list = has('GetWindowDrawList')
    caps.add_image = caps.draw_list and has('ImDrawList')
    caps.invisible_button = has('InvisibleButton')
    caps.get_cursor_screen_pos = has('GetCursorScreenPos')
    caps.same_line = has('SameLine')
    caps.imvec2 = has('ImVec2')
    caps.imvec4 = has('ImVec4')
    caps.style = has('GetStyle')
    caps.style_colors = has('StyleColorsDark') and has('StyleColorsLight')
    caps.new_int = has_new('int')
    caps.new_bool = has_new('bool')
    caps.new_float = has_new('float')
    caps.font_atlas = has('GetIO') and has('ImFontConfig') and has('ImFontGlyphRangesBuilder')
    caps.font_rebuild = has('CreateFontsTexture') and has('InvalidateFontsTexture')
    caps.push_font = has('PushFont') and has('PopFont')
    caps.texture_file = has('CreateTextureFromFile')
    caps.texture_memory = has('CreateTextureFromFileInMemory')
    caps.release_texture = has('ReleaseTexture')
    caps.time = has('GetTime')
    caps.input_text = has('InputText')
    caps.slider_float = has('SliderFloat')
    caps.combo = has('Combo')
    caps.selectable = has('Selectable')
    caps.popup_modal = has('BeginPopupModal')
    caps.tooltip = has('BeginTooltip') and has('EndTooltip')
    caps.dpi_scale = type(_G.MONET_DPI_SCALE) == 'number'
    caps.working_directory = has_global('getWorkingDirectory')
    caps.file_exists = has_global('doesFileExist')
    caps.screen_resolution = has_global('getScreenResolution')
    caps.event_handler = has_global('addEventHandler')
    return caps
end

function M.capabilities()
    if capabilities == nil then
        capabilities = build_capabilities()
    end
    local out = {}
    for name, value in pairs(capabilities) do
        out[name] = value
    end
    return out
end

local subscriptions = {}
local shutdown_handlers = {}

local function require_callback(value, name)
    if type(value) ~= 'function' then
        error('nimgui.render: ' .. name .. ' must be a function', 2)
    end
end

function M.render(cond, before, draw)
    require_callback(cond, 'condition')
    if draw == nil then
        draw = before
        before = nil
    end
    require_callback(draw, 'draw')
    if before ~= nil then
        require_callback(before, 'before')
    end

    local function safe_draw()
        local ok, err = pcall(draw)
        if ok then
            ok, err = pcall(widgets.draw_toast)
        end
        if not ok then
            layout.reset()
            theme.pop_all()
            error(err, 0)
        end
    end

    local sub = imgui.OnFrame(cond, before or function() end, safe_draw)
    subscriptions[#subscriptions + 1] = sub
    return sub
end

function M.add_shutdown_handler(fn)
    if type(fn) ~= 'function' then
        error('nimgui.add_shutdown_handler: handler must be a function', 2)
    end
    shutdown_handlers[#shutdown_handlers + 1] = fn
end

function M.shutdown()
    local first_err = nil

    for i = #shutdown_handlers, 1, -1 do
        local fn = shutdown_handlers[i]
        shutdown_handlers[i] = nil
        local ok, err = pcall(fn)
        if not ok and first_err == nil then
            first_err = err
        end
    end

    for i = #subscriptions, 1, -1 do
        local sub = subscriptions[i]
        subscriptions[i] = nil
        if sub and type(sub.Unsubscribe) == 'function' then
            local ok, err = pcall(function() sub:Unsubscribe() end)
            if not ok and first_err == nil then
                first_err = err
            end
        end
    end

    layout.reset()
    widgets.reset()

    local _, release_err = media.release_all()
    if release_err ~= nil and first_err == nil then
        first_err = release_err
    end

    theme.pop_all()

    if first_err ~= nil then
        return false, first_err
    end
    return true
end

M.theme = theme.make
M.scale = theme.scale
M.state = state.create
M.media = media
M.fonts = fonts

M.begin_panel = layout.begin_panel
M.end_panel = layout.end_panel
M.begin_child = layout.begin_child
M.end_child = layout.end_child
M.spacer = layout.spacer
M.same_line = layout.same_line
M.separator = layout.separator
M.grid_columns = layout.grid_columns
M.truncate = layout.truncate
M.footer_height = layout.footer_height

M.button = widgets.button
M.segmented = widgets.segmented
M.toggle = widgets.toggle
M.checkbox = widgets.checkbox
M.slider = widgets.slider
M.input_int = widgets.input_int
M.input_float = widgets.input_float
M.input_text = widgets.input_text
M.stat_tile = widgets.stat_tile
M.progress = widgets.progress
M.empty = widgets.empty
M.tooltip = widgets.tooltip
M.modal = widgets.modal
M.toast = widgets.toast

return M
