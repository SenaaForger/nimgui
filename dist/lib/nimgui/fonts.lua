-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

-- Font manager: one base font per named size, plus one merged icon font.
-- setup() must run inside OnInitialize, before the first NewFrame.

local imgui = require 'mimgui'

local M = {}

local EXTRA_TEXT = [[‚„…†‡€‰‹‘’“”•–™›№]]

local registry = nil

local function fail(fmt, ...)
    return nil, string.format('nimgui.fonts.setup: ' .. fmt, ...)
end

local function reject(message)
    return nil, 'nimgui.fonts.setup: ' .. message
end

local function host_dpi()
    local dpi = _G.MONET_DPI_SCALE
    if type(dpi) == 'number' and dpi > 0 then
        return dpi
    end
    return 1.0
end

local function file_exists(path)
    local check = _G.doesFileExist
    if type(check) ~= 'function' then
        return true
    end
    local ok, value = pcall(check, path)
    return ok and value == true
end

local function base_ranges()
    local atlas = imgui.GetIO().Fonts
    local builder = imgui.ImFontGlyphRangesBuilder()
    local ok, ranges = pcall(function() return atlas:GetGlyphRangesCyrillic() end)
    if ok and ranges ~= nil then
        builder:AddRanges(ranges)
    else
        builder:AddRanges(atlas:GetGlyphRangesDefault())
    end
    builder:AddText(EXTRA_TEXT)
    local vector = imgui.ImVector_ImWchar()
    builder:BuildRanges(vector)
    return builder, vector
end

local function icon_ranges(codepoints)
    local builder = imgui.ImFontGlyphRangesBuilder()
    for index = 1, #codepoints do
        local value = codepoints[index]
        if type(value) == 'number' then
            if value < 1 or value > 0xFFFF then
                return nil, string.format('codepoint %d is outside the 16-bit range', value)
            end
            builder:AddChar(value)
        elseif type(value) == 'string' and value ~= '' then
            builder:AddText(value)
        else
            return nil, string.format('codepoint %d must be a number or a UTF-8 string', index)
        end
    end
    local vector = imgui.ImVector_ImWchar()
    builder:BuildRanges(vector)
    return builder, vector
end

local function collect_sizes(opts)
    local sizes = opts.sizes
    if sizes == nil then
        local base = opts.base
        local size = base.size or 14
        return { body = size }, nil
    end
    if type(sizes) ~= 'table' then
        return nil, 'sizes must be a table'
    end

    local names = {}
    for name, size in pairs(sizes) do
        if type(name) ~= 'string' or name == '' then
            return nil, 'size names must be non-empty strings'
        end
        if type(size) ~= 'number' or size <= 0 then
            return nil, string.format('size "%s" must be a positive number', name)
        end
        names[#names + 1] = name
    end
    if #names == 0 then
        return nil, 'sizes must contain at least one entry'
    end
    table.sort(names)

    local ordered = {}
    for index = 1, #names do
        ordered[names[index]] = sizes[names[index]]
    end
    return ordered, names
end

local function primary_name(sizes, names)
    if sizes.body ~= nil then
        return 'body'
    end
    return names[1]
end

function M.setup(opts)
    if registry ~= nil then
        return true
    end
    if type(opts) ~= 'table' then
        return fail('options are required')
    end

    local base = opts.base
    if type(base) ~= 'table' then
        return fail('base is required')
    end
    if type(base.path) ~= 'string' or base.path == '' then
        return fail('base.path must be a non-empty string')
    end
    if base.size ~= nil and (type(base.size) ~= 'number' or base.size <= 0) then
        return fail('base.size must be a positive number')
    end
    if not file_exists(base.path) then
        return fail('font not found: %s', base.path)
    end

    local dpi = opts.dpi
    if dpi == nil then
        dpi = host_dpi()
    end
    if type(dpi) ~= 'number' or dpi <= 0 then
        return fail('dpi must be a positive number')
    end

    local sizes, names = collect_sizes(opts)
    if sizes == nil then
        return reject(names)
    end
    names = names or { 'body' }
    local primary = primary_name(sizes, names)

    local icons = opts.icons
    local icon_builder, icon_vector, icon_cfg, icon_size = nil, nil, nil, nil
    if icons ~= nil then
        if type(icons) ~= 'table' then
            return fail('icons must be a table')
        end
        local has_path = type(icons.path) == 'string' and icons.path ~= ''
        local has_data = type(icons.data_base85) == 'string' and icons.data_base85 ~= ''
        if not has_path and not has_data then
            return fail('icons.path or icons.data_base85 is required')
        end
        if has_path and not file_exists(icons.path) then
            return fail('icon font not found: %s', icons.path)
        end
        if type(icons.codepoints) ~= 'table' or #icons.codepoints == 0 then
            return fail('icons.codepoints must be a non-empty array')
        end

        icon_builder, icon_vector = icon_ranges(icons.codepoints)
        if icon_builder == nil then
            return reject(icon_vector)
        end

        icon_size = icons.size or sizes[primary]
        if type(icon_size) ~= 'number' or icon_size <= 0 then
            return fail('icons.size must be a positive number')
        end

        icon_cfg = imgui.ImFontConfig()
        icon_cfg.MergeMode = true
    end

    local base_builder, base_vector = base_ranges()
    local atlas = imgui.GetIO().Fonts
    local textures_ready = atlas:IsBuilt() or atlas.TexID ~= nil
    local fonts = {}

    for index = 1, #names do
        local name = names[index]
        local size = sizes[name] * dpi
        local font = atlas:AddFontFromFileTTF(base.path, size, nil, base_vector[0].Data)
        if font == nil then
            return fail('could not load %s', base.path)
        end
        fonts[name] = font

        if icons ~= nil and name == primary then
            local icon_font
            if icons.path ~= nil then
                icon_font = atlas:AddFontFromFileTTF(
                    icons.path, icon_size * dpi, icon_cfg, icon_vector[0].Data)
            else
                icon_font = atlas:AddFontFromMemoryCompressedBase85TTF(
                    icons.data_base85, icon_size * dpi, icon_cfg, icon_vector[0].Data)
            end
            if icon_font == nil then
                return fail('could not load the icon font')
            end
        end
    end

    if textures_ready and imgui.InvalidateFontsTexture ~= nil then
        imgui.InvalidateFontsTexture()
    end

    registry = {
        fonts = fonts,
        names = names,
        primary = primary,
        dpi = dpi,
        keepalive = {
            base_builder = base_builder,
            base_vector = base_vector,
            icon_builder = icon_builder,
            icon_vector = icon_vector,
            icon_cfg = icon_cfg,
            icon_data = icons and icons.data_base85 or nil,
        },
    }
    return true
end

function M.ready()
    return registry ~= nil
end

function M.push(name)
    if registry == nil then
        return nil, 'nimgui.fonts: setup() has not run'
    end
    local font = registry.fonts[name]
    if font == nil then
        return nil, string.format('nimgui.fonts: unknown size "%s"', tostring(name))
    end
    imgui.PushFont(font)
    return true
end

function M.pop()
    if registry == nil then
        return nil, 'nimgui.fonts: setup() has not run'
    end
    imgui.PopFont()
    return true
end

return M
