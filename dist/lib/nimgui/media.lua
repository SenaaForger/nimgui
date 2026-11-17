-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

-- Texture registry, animated GIF playback, and budget accounting.
-- Textures are created once at load time; draw helpers never upload.

local ffi = require 'ffi'
local imgui = require 'mimgui'
local theme = require 'nimgui.theme'
local gif = require 'nimgui.gif'

local M = {}

local DEFAULTS = {
    max_frames = 120,
    max_atlas_pixels = 2000000,
    max_dimension = 4096,
}

local stats = {
    textures = 0,
    atlas_pixels = 0,
    frames = 0,
}

local live = {}
local white = nil
local clear = nil

local function full_uvs()
    if clear == nil then
        clear = imgui.ImVec4(0, 0, 0, 0)
        white = imgui.ImVec4(1, 1, 1, 1)
    end
    return white, clear
end

local function frame_dt()
    local ok, io = pcall(imgui.GetIO)
    if ok and io then
        local dt = tonumber(io.DeltaTime)
        if dt and dt > 0 then
            return math.min(dt, 0.1)
        end
    end
    return 0.016
end

local function make_opts(opts)
    opts = opts or {}
    return {
        max_frames = opts.max_frames or DEFAULTS.max_frames,
        max_atlas_pixels = opts.max_atlas_pixels or DEFAULTS.max_atlas_pixels,
        max_dimension = opts.max_dimension or DEFAULTS.max_dimension,
        allow_scale = opts.allow_scale,
        width = opts.width,
        height = opts.height,
    }
end

local function is_gif(data)
    return type(data) == 'string'
        and (data:sub(1, 6) == 'GIF87a' or data:sub(1, 6) == 'GIF89a')
end

local function upload(buffer, size)
    local texture = imgui.CreateTextureFromFileInMemory(buffer, size)
    if texture == nil then
        return nil, 'texture upload failed'
    end
    return texture
end

local function upload_atlas(atlas)
    local buffer, size = gif.encode_bmp(atlas)
    local texture, err = upload(buffer, size)
    if texture ~= nil then
        return texture
    end

    buffer, size = gif.encode_tga(atlas)
    local fallback, fallback_err = upload(buffer, size)
    if fallback ~= nil then
        return fallback
    end
    return nil, err .. '; ' .. fallback_err
end

local function new_handle()
    return {
        tex = nil,
        width = 0,
        height = 0,
        atlas_width = 0,
        atlas_height = 0,
        atlas_pixels = 0,
        cell_width = 0,
        cell_height = 0,
        scale = 1,
        frame_count = 0,
        loop_count = 0,
        frames = {},
        uv0 = nil,
        uv1 = nil,
        animated = false,
        frame_index = 1,
        elapsed = 0,
        loops_done = 0,
        stopped = false,
        released = false,
        fallback = nil,
        loading = false,
        failed = false,
        progress = 1,
        decoder = nil,
        accounted = false,
    }
end

local function apply_atlas(handle, texture, atlas, animated)
    local frames = {}
    for index = 1, atlas.frame_count do
        local col = (index - 1) % atlas.cols
        local row = math.floor((index - 1) / atlas.cols)
        local meta = atlas.frames[index]
        frames[index] = {
            delay = (meta and meta.delay or 100) / 1000,
            uv0 = imgui.ImVec2(col / atlas.cols, row / atlas.rows),
            uv1 = imgui.ImVec2((col + 1) / atlas.cols, (row + 1) / atlas.rows),
        }
    end

    handle.tex = texture
    handle.width = atlas.width
    handle.height = atlas.height
    handle.atlas_width = atlas.atlas_width
    handle.atlas_height = atlas.atlas_height
    handle.atlas_pixels = atlas.atlas_pixels
    handle.cell_width = atlas.cell_width or atlas.width
    handle.cell_height = atlas.cell_height or atlas.height
    handle.scale = atlas.scale or 1
    handle.frame_count = atlas.frame_count
    handle.loop_count = atlas.loop_count
    handle.frames = frames
    handle.uv0 = frames[1].uv0
    handle.uv1 = frames[1].uv1
    handle.animated = animated and atlas.frame_count > 1
    handle.frame_index = 1
    handle.elapsed = 0
    handle.loops_done = 0
    handle.stopped = false
    handle.loading = false
    handle.failed = false
    handle.progress = 1
    handle.error = nil
    handle.decoder = nil
    handle.accounted = true

    stats.textures = stats.textures + 1
    stats.atlas_pixels = stats.atlas_pixels + handle.atlas_pixels
    stats.frames = stats.frames + handle.frame_count
    live[handle] = true
    return handle
end

local function add_handle(texture, atlas, animated)
    return apply_atlas(new_handle(), texture, atlas, animated)
end

local function add_raw(texture, opts)
    local pixels = 0
    if type(opts.width) == 'number' and type(opts.height) == 'number' then
        pixels = opts.width * opts.height
    end
    local handle = {
        tex = texture,
        width = opts.width,
        height = opts.height,
        atlas_width = opts.width,
        atlas_height = opts.height,
        atlas_pixels = pixels,
        frame_count = 1,
        loop_count = 0,
        frames = {
            {
                delay = 0.1,
                uv0 = imgui.ImVec2(0, 0),
                uv1 = imgui.ImVec2(1, 1),
            },
        },
        uv0 = imgui.ImVec2(0, 0),
        uv1 = imgui.ImVec2(1, 1),
        animated = false,
        frame_index = 1,
        elapsed = 0,
        loops_done = 0,
        stopped = false,
        released = false,
        fallback = nil,
        loading = false,
        failed = false,
        progress = 1,
        decoder = nil,
        accounted = true,
    }
    stats.textures = stats.textures + 1
    stats.atlas_pixels = stats.atlas_pixels + pixels
    stats.frames = stats.frames + 1
    live[handle] = true
    return handle
end

function M.load_bytes(data, size, opts)
    if type(data) ~= 'string' then
        return nil, 'nimgui.media.load_bytes: data must be a string'
    end
    size = size or #data
    if type(size) ~= 'number' or size < 1 or size > #data then
        return nil, 'nimgui.media.load_bytes: size is out of range'
    end

    local gif_format = is_gif(data)
    if size < #data then
        data = data:sub(1, size)
    end
    local options = make_opts(opts)
    if gif_format then
        if size < 6 then
            return nil, 'nimgui.media.load_bytes: truncated GIF'
        end
        local atlas, err = gif.first_frame(data, options)
        if atlas == nil then
            return nil, err
        end
        local texture, upload_err = upload_atlas(atlas)
        if texture == nil then
            return nil, upload_err
        end
        return add_handle(texture, atlas, false)
    end

    local texture, err = upload(data, size)
    if texture == nil then
        return nil, err
    end
    return add_raw(texture, options)
end

function M.load_file(path, opts)
    if type(path) ~= 'string' or path == '' then
        return nil, 'nimgui.media.load_file: path must be a non-empty string'
    end
    local file, open_err = io.open(path, 'rb')
    if file == nil then
        return nil, 'nimgui.media.load_file: ' .. tostring(open_err)
    end
    local data, read_err = file:read('*a')
    file:close()
    if data == nil then
        return nil, 'nimgui.media.load_file: ' .. tostring(read_err)
    end
    return M.load_bytes(data, #data, opts)
end

local function gif_input(data, size, label)
    if type(data) ~= 'string' then
        return nil, label .. ': data must be a string'
    end
    size = size or #data
    if type(size) ~= 'number' or size < 1 or size > #data then
        return nil, label .. ': size is out of range'
    end
    if size < 6 then
        return nil, label .. ': truncated GIF'
    end
    if size < #data then
        data = data:sub(1, size)
    end
    if not is_gif(data) then
        return nil, label .. ': data is not a GIF'
    end
    return data
end

function M.anim_bytes(data, size, opts)
    local checked, input_err = gif_input(data, size, 'nimgui.media.anim_bytes')
    if checked == nil then
        return nil, input_err
    end
    data = checked

    local options = make_opts(opts)
    local atlas, err = gif.decode(data, options)
    if atlas ~= nil then
        local texture, upload_err = upload_atlas(atlas)
        if texture ~= nil then
            return add_handle(texture, atlas, true)
        end
        err = upload_err
    end

    local first, first_err = gif.first_frame(data, options)
    if first == nil then
        return nil, err .. '; static fallback: ' .. first_err
    end
    local texture, upload_err = upload_atlas(first)
    if texture == nil then
        return nil, err .. '; static fallback: ' .. upload_err
    end
    local handle = add_handle(texture, first, false)
    handle.fallback = err
    return handle
end

function M.anim(path, opts)
    if type(path) ~= 'string' or path == '' then
        return nil, 'nimgui.media.anim: path must be a non-empty string'
    end
    local file, open_err = io.open(path, 'rb')
    if file == nil then
        return nil, 'nimgui.media.anim: ' .. tostring(open_err)
    end
    local data, read_err = file:read('*a')
    file:close()
    if data == nil then
        return nil, 'nimgui.media.anim: ' .. tostring(read_err)
    end
    return M.anim_bytes(data, #data, opts)
end

local function new_loading(decoder)
    local handle = new_handle()
    handle.loading = true
    handle.progress = 0
    handle.decoder = decoder
    handle.width = decoder.width
    handle.height = decoder.height
    handle.cell_width = decoder.cell_width
    handle.cell_height = decoder.cell_height
    handle.scale = decoder.scale
    handle.frame_count = decoder.frame_count
    handle.loop_count = decoder.loop_count
    live[handle] = true
    return handle
end

function M.anim_bytes_async(data, size, opts)
    local checked, input_err = gif_input(data, size, 'nimgui.media.anim_bytes_async')
    if checked == nil then
        return nil, input_err
    end
    local decoder, err = gif.decoder(checked, make_opts(opts))
    if decoder == nil then
        return nil, err
    end
    return new_loading(decoder)
end

function M.anim_async(path, opts)
    if type(path) ~= 'string' or path == '' then
        return nil, 'nimgui.media.anim_async: path must be a non-empty string'
    end
    local file, open_err = io.open(path, 'rb')
    if file == nil then
        return nil, 'nimgui.media.anim_async: ' .. tostring(open_err)
    end
    local data, read_err = file:read('*a')
    file:close()
    if data == nil then
        return nil, 'nimgui.media.anim_async: ' .. tostring(read_err)
    end
    return M.anim_bytes_async(data, #data, opts)
end

function M.step_anim(handle, budget_ms)
    if type(handle) ~= 'table' then
        return nil, 'nimgui.media.step_anim: handle must be a table'
    end
    if handle.released then
        return false, 'nimgui.media.step_anim: handle is released'
    end
    if not handle.loading then
        if handle.failed then
            return false, handle.error
        end
        return true
    end

    local decoder = handle.decoder
    if decoder == nil then
        handle.loading = false
        handle.failed = true
        handle.error = 'nimgui.media.step_anim: decoder is missing'
        return false, handle.error
    end

    local budget = tonumber(budget_ms) or 8
    if budget < 1 then
        budget = 1
    end
    local deadline = os.clock() + budget / 1000
    local finished = false

    while true do
        local status, err = decoder:step(64)
        if status == nil then
            handle.loading = false
            handle.failed = true
            handle.error = err
            handle.decoder = nil
            return false, err
        end
        if status == 'done' then
            finished = true
            break
        end
        if os.clock() >= deadline then
            break
        end
    end

    if not finished then
        local done = decoder.frame_index - 1
        handle.progress = math.min(0.99, done / decoder.frame_count)
        return nil
    end

    local atlas = decoder:result()
    handle.decoder = nil
    local texture, err = upload_atlas(atlas)
    if texture == nil then
        handle.loading = false
        handle.failed = true
        handle.error = err
        return false, err
    end
    apply_atlas(handle, texture, atlas, true)
    return true
end

function M.release(handle)
    if type(handle) ~= 'table' then
        return false, 'nimgui.media.release: handle must be a table'
    end
    if handle.released then
        return true
    end

    handle.released = true
    live[handle] = nil
    handle.decoder = nil
    if handle.accounted then
        stats.textures = math.max(0, stats.textures - 1)
        stats.atlas_pixels = math.max(0, stats.atlas_pixels - (handle.atlas_pixels or 0))
        stats.frames = math.max(0, stats.frames - (handle.frame_count or 0))
    end

    local texture = handle.tex
    handle.tex = nil
    if texture ~= nil then
        pcall(ffi.gc, texture, nil)
        local ok, err = pcall(imgui.ReleaseTexture, texture)
        if not ok then
            return false, tostring(err)
        end
    end
    return true
end

function M.release_all()
    local handles = {}
    for handle in pairs(live) do
        handles[#handles + 1] = handle
    end

    local released = 0
    local first_err = nil
    for index = 1, #handles do
        local ok, err = M.release(handles[index])
        if ok then
            released = released + 1
        elseif first_err == nil then
            first_err = err
        end
    end
    return released, first_err
end

function M.stats()
    return {
        textures = stats.textures,
        atlas_pixels = stats.atlas_pixels,
        frames = stats.frames,
        estimated_bytes = stats.atlas_pixels * 4,
    }
end

function M.placeholder(width, height, opts)
    opts = opts or {}
    if type(width) ~= 'number' or type(height) ~= 'number'
        or width <= 0 or height <= 0 then
        error('nimgui.media.placeholder: width and height must be positive', 2)
    end

    local active = opts.theme or theme.active()
    local pos = imgui.GetCursorScreenPos()
    imgui.Dummy(imgui.ImVec2(width, height))
    local draw_list = imgui.GetWindowDrawList and imgui.GetWindowDrawList()
    if draw_list == nil then
        return
    end
    local top_left = imgui.ImVec2(pos.x, pos.y)
    local bottom_right = imgui.ImVec2(pos.x + width, pos.y + height)
    local radius = active.radius
    draw_list:AddRectFilled(top_left, bottom_right, active.color.raised, radius)
    draw_list:AddRect(top_left, bottom_right, active.color.border, radius)

    local label = opts.label or 'Gambar tidak tersedia'
    local label_size = imgui.CalcTextSize(label)
    draw_list:AddText(
        imgui.ImVec2(pos.x + (width - label_size.x) / 2, pos.y + (height - label_size.y) / 2),
        active.color.muted,
        label)
end

function M.image(handle, width, height, opts)
    if type(width) ~= 'number' or type(height) ~= 'number'
        or width <= 0 or height <= 0 then
        error('nimgui.media.image: width and height must be positive', 2)
    end
    if type(handle) ~= 'table' or handle.released or handle.tex == nil then
        return M.placeholder(width, height, opts)
    end
    opts = opts or {}
    local tint, border = full_uvs()
    imgui.Image(
        handle.tex,
        imgui.ImVec2(width, height),
        handle.uv0,
        handle.uv1,
        opts.tint or tint,
        opts.border or border)
end

local function advance(handle, dt)
    if handle.stopped or handle.frame_count < 2 then
        return
    end

    handle.elapsed = handle.elapsed + dt
    local delay = handle.frames[handle.frame_index].delay
    if delay <= 0 then
        delay = 0.1
    end

    local guard = 0
    while handle.elapsed >= delay do
        handle.elapsed = handle.elapsed - delay
        if handle.frame_index == handle.frame_count then
            handle.loops_done = handle.loops_done + 1
            if handle.loop_count == 0 or handle.loops_done <= handle.loop_count then
                handle.frame_index = 1
            else
                handle.stopped = true
                handle.frame_index = handle.frame_count
                return
            end
        else
            handle.frame_index = handle.frame_index + 1
        end
        guard = guard + 1
        if guard > 1000 then
            return
        end
        delay = handle.frames[handle.frame_index].delay
        if delay <= 0 then
            delay = 0.1
        end
    end
end

function M.draw_anim(handle, width, height, dt, opts)
    if type(width) ~= 'number' or type(height) ~= 'number'
        or width <= 0 or height <= 0 then
        error('nimgui.media.draw_anim: width and height must be positive', 2)
    end
    if type(handle) == 'table' and handle.loading and not handle.released then
        M.step_anim(handle, opts and opts.budget or 8)
    end
    if type(handle) ~= 'table' or handle.released then
        M.placeholder(width, height, { label = 'Animasi tidak tersedia' })
        return nil
    end
    if handle.loading then
        local percent = math.floor((handle.progress or 0) * 100 + 0.5)
        M.placeholder(width, height, {
            label = string.format('Memuat GIF %d%%', percent),
        })
        return nil
    end
    if handle.failed or handle.tex == nil then
        M.placeholder(width, height, {
            label = handle.failed and 'GIF gagal dimuat' or 'Animasi tidak tersedia',
        })
        return nil
    end
    if not handle.animated then
        M.image(handle, width, height)
        return 1
    end

    if theme.active().reduce_motion then
        handle.frame_index = 1
    else
        advance(handle, dt or frame_dt())
    end

    local frame = handle.frames[handle.frame_index]
    local pos = imgui.GetCursorScreenPos()
    imgui.Dummy(imgui.ImVec2(width, height))
    local draw_list = imgui.GetWindowDrawList and imgui.GetWindowDrawList()
    if draw_list ~= nil then
        draw_list:AddImage(
            handle.tex,
            imgui.ImVec2(pos.x, pos.y),
            imgui.ImVec2(pos.x + width, pos.y + height),
            frame.uv0,
            frame.uv1,
            0xFFFFFFFF)
    else
        local tint, border = full_uvs()
        imgui.Image(
            handle.tex,
            imgui.ImVec2(width, height),
            frame.uv0,
            frame.uv1,
            tint,
            border)
    end
    return handle.frame_index
end

return M
