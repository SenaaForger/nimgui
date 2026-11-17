-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

-- Pure-Lua GIF decoder and atlas encoder.
-- The decoder composites frames into one grid atlas so a single texture upload
-- is enough. BMP/TGA output is consumed by mimgui/CreateTextureFromFileInMemory.

local ffi = require 'ffi'

local M = {}

local DEFAULTS = {
    max_frames = 120,
    max_atlas_pixels = 2000000,
    max_canvas_pixels = 4000000,
    max_dimension = 4096,
    step_rows = 64,
}

local function fail(fmt, ...)
    error(string.format('gif: ' .. fmt, ...), 0)
end

local function clean(err)
    return type(err) == 'string' and err or tostring(err)
end

local function u16le(value)
    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function u32le(value)
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256)
end

local function make_opts(opts)
    opts = opts or {}
    local out = {}
    for name, default in pairs(DEFAULTS) do
        local value = opts[name]
        if value == nil then
            value = default
        elseif type(value) ~= 'number' or value < 1 then
            fail('%s must be a positive number', name)
        end
        out[name] = math.floor(value)
    end
    out.allow_scale = opts.allow_scale ~= false
    if opts.limit_frames ~= nil then
        out.limit_frames = opts.limit_frames
    end
    return out
end

local function delay_ms(centiseconds)
    if centiseconds <= 1 then
        return 100
    end
    return centiseconds * 10
end

-- ---------------------------------------------------------------------------
-- Block parser
-- ---------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function new_parser(data)
    if type(data) ~= 'string' then
        fail('data must be a string')
    end
    if #data < 13 then
        fail('truncated header')
    end
    if data:sub(1, 6) ~= 'GIF87a' and data:sub(1, 6) ~= 'GIF89a' then
        fail('not a GIF')
    end
    return setmetatable({ data = data, pos = 7, len = #data }, Parser)
end

function Parser:need(count)
    if self.pos + count - 1 > self.len then
        fail('truncated data at byte %d', self.pos)
    end
end

function Parser:u8()
    if self.pos > self.len then
        fail('truncated data at byte %d', self.pos)
    end
    local value = self.data:byte(self.pos)
    self.pos = self.pos + 1
    return value
end

function Parser:u16()
    local low = self:u8()
    local high = self:u8()
    return low + high * 256
end

function Parser:skip(count)
    self:need(count)
    self.pos = self.pos + count
end

function Parser:color_table(size)
    self:need(size * 3)
    local palette = {}
    local data, pos = self.data, self.pos
    for index = 0, size - 1 do
        local offset = index * 3
        palette[offset + 1] = data:byte(pos)
        palette[offset + 2] = data:byte(pos + 1)
        palette[offset + 3] = data:byte(pos + 2)
        pos = pos + 3
    end
    self.pos = pos
    return palette
end

function Parser:skip_blocks()
    while true do
        local size = self:u8()
        if size == 0 then
            return
        end
        self:skip(size)
    end
end

function Parser:application()
    local loop_count = 0
    while true do
        local size = self:u8()
        if size == 0 then
            return loop_count
        end
        if size >= 3 then
            local ident = self:u8()
            local low = self:u8()
            local high = self:u8()
            if ident == 1 then
                loop_count = low + high * 256
            end
            if size > 3 then
                self:skip(size - 3)
            end
        else
            self:skip(size)
        end
    end
end

local function parse_raw(data, opts)
    local p = new_parser(data)
    local width = p:u16()
    local height = p:u16()
    local packed = p:u8()
    local background = p:u8()
    p:u8() -- pixel aspect ratio

    if width == 0 or height == 0 then
        fail('empty logical screen')
    end

    local global_palette = nil
    if packed >= 128 then
        global_palette = p:color_table(2 ^ ((packed % 8) + 1))
    end

    local frames = {}
    local loop_count = 0
    local pending = nil

    while true do
        local marker = p:u8()
        if marker == 0x3B then
            break
        elseif marker == 0x21 then
            local label = p:u8()
            if label == 0xF9 then
                local size = p:u8()
                if size ~= 4 then
                    fail('bad graphic control block')
                end
                local flags = p:u8()
                local delay = p:u16()
                local transparent = p:u8()
                local terminator = p:u8()
                if terminator ~= 0 then
                    fail('bad graphic control terminator')
                end
                pending = {
                    disposal = math.floor(flags / 4) % 8,
                    delay_cs = delay,
                    transparent = (flags % 2 == 1) and transparent or nil,
                }
            elseif label == 0xFF then
                local size = p:u8()
                if size == 11 then
                    p:need(11)
                    local name = p.data:sub(p.pos, p.pos + 10)
                    p:skip(11)
                    if name == 'NETSCAPE2.0' or name == 'ANIMEXTS1.0' then
                        loop_count = p:application()
                    else
                        p:skip_blocks()
                    end
                else
                    p:skip(size)
                    p:skip_blocks()
                end
            elseif label == 0x01 then
                local size = p:u8()
                p:skip(size)
                p:skip_blocks()
            else
                p:skip_blocks()
            end
        elseif marker == 0x2C then
            local x = p:u16()
            local y = p:u16()
            local frame_w = p:u16()
            local frame_h = p:u16()
            local flags = p:u8()
            if frame_w == 0 or frame_h == 0 then
                fail('empty image frame')
            end

            local palette = global_palette
            if flags >= 128 then
                palette = p:color_table(2 ^ ((flags % 8) + 1))
            end
            if palette == nil then
                fail('frame without a color table')
            end

            local min_code = p:u8()
            if min_code < 2 or min_code > 8 then
                fail('bad LZW minimum code size %d', min_code)
            end

            local data_start = p.pos
            p:skip_blocks()

            local gce = pending or {}
            pending = nil
            frames[#frames + 1] = {
                x = x,
                y = y,
                w = frame_w,
                h = frame_h,
                interlaced = math.floor(flags / 64) % 2 == 1,
                palette = palette,
                min_code = min_code,
                data_start = data_start,
                disposal = gce.disposal or 0,
                delay_cs = gce.delay_cs or 0,
                transparent = gce.transparent,
            }

            if opts.limit_frames and #frames >= opts.limit_frames then
                break
            end
        else
            fail('unknown block 0x%02X at byte %d', marker, p.pos - 1)
        end
    end

    if #frames == 0 then
        fail('no frames')
    end

    return {
        width = width,
        height = height,
        background = background,
        global_palette = global_palette,
        frames = frames,
        loop_count = loop_count,
    }
end

-- ---------------------------------------------------------------------------
-- Atlas planning
-- ---------------------------------------------------------------------------

local function layout_atlas(cell_w, cell_h, count, max_dimension, max_pixels)
    local best = nil
    for cols = 1, count do
        local rows = math.ceil(count / cols)
        local atlas_w = cols * cell_w
        local atlas_h = rows * cell_h
        if atlas_w <= max_dimension and atlas_h <= max_dimension then
            local area = atlas_w * atlas_h
            if area <= max_pixels and (best == nil or area < best.area) then
                best = {
                    cols = cols,
                    rows = rows,
                    width = atlas_w,
                    height = atlas_h,
                    area = area,
                    cell_width = cell_w,
                    cell_height = cell_h,
                }
            end
        end
    end
    return best
end

local function fit_atlas(width, height, count, opts)
    local best = layout_atlas(
        width, height, count, opts.max_dimension, opts.max_atlas_pixels)
    if best ~= nil then
        best.scale = 1
        return best
    end

    local low, high = 0, 1
    for _ = 1, 32 do
        local mid = (low + high) / 2
        local cell_w = math.max(1, math.floor(width * mid))
        local cell_h = math.max(1, math.floor(height * mid))
        local layout = layout_atlas(
            cell_w, cell_h, count, opts.max_dimension, opts.max_atlas_pixels)
        if layout ~= nil then
            layout.scale = cell_w / width
            best = layout
            low = mid
        else
            high = mid
        end
    end
    return best
end

local function plan_atlas(info, opts)
    local width, height = info.width, info.height
    if width > opts.max_dimension or height > opts.max_dimension then
        return nil, string.format(
            'gif: logical screen %dx%d exceeds max dimension %d',
            width, height, opts.max_dimension)
    end
    if width * height > opts.max_canvas_pixels then
        return nil, string.format(
            'gif: logical screen needs %d pixels, canvas budget is %d',
            width * height, opts.max_canvas_pixels)
    end

    local count = #info.frames
    if count > opts.max_frames then
        return nil, string.format(
            'gif: %d frames exceeds budget of %d', count, opts.max_frames)
    end

    for index = 1, count do
        local frame = info.frames[index]
        if frame.w > opts.max_dimension or frame.h > opts.max_dimension then
            return nil, string.format(
                'gif: frame %d is %dx%d, max dimension is %d',
                index, frame.w, frame.h, opts.max_dimension)
        end
        if frame.w * frame.h > opts.max_canvas_pixels then
            return nil, string.format(
                'gif: frame %d needs %d pixels, canvas budget is %d',
                index, frame.w * frame.h, opts.max_canvas_pixels)
        end
    end

    if not opts.allow_scale then
        local strict = layout_atlas(
            width, height, count, opts.max_dimension, math.huge)
        if strict == nil then
            return nil, string.format(
                'gif: atlas does not fit %d x %d',
                opts.max_dimension, opts.max_dimension)
        end
        if strict.area > opts.max_atlas_pixels then
            return nil, string.format(
                'gif: atlas needs %d pixels, budget is %d',
                strict.area, opts.max_atlas_pixels)
        end
        strict.scale = 1
        return strict
    end

    local best = fit_atlas(width, height, count, opts)
    if best == nil then
        return nil, string.format(
            'gif: animation needs at least %d pixels, budget is %d',
            count, opts.max_atlas_pixels)
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Decoder
-- ---------------------------------------------------------------------------

local Decoder = {}
Decoder.__index = Decoder

local function make_decoder(data, info, plan, opts)
    local cell_width = plan.cell_width
    local cell_height = plan.cell_height
    local x_map = ffi.new('uint32_t[?]', cell_width)
    local y_map = ffi.new('uint32_t[?]', cell_height)
    for x = 0, cell_width - 1 do
        x_map[x] = math.floor(x * info.width / cell_width)
    end
    for y = 0, cell_height - 1 do
        y_map[y] = math.floor(y * info.height / cell_height)
    end

    local decoder = setmetatable({
        data = data,
        bytes = ffi.cast('const uint8_t*', data),
        data_len = #data,
        width = info.width,
        height = info.height,
        frames = info.frames,
        frame_count = #info.frames,
        loop_count = info.loop_count,
        cols = plan.cols,
        rows = plan.rows,
        atlas_width = plan.width,
        atlas_height = plan.height,
        atlas_pixels = plan.area,
        cell_width = cell_width,
        cell_height = cell_height,
        scale = plan.scale,
        x_map = x_map,
        y_map = y_map,
        atlas = ffi.new('uint8_t[?]', plan.area * 4),
        canvas = ffi.new('uint8_t[?]', info.width * info.height * 4),
        step_rows = opts.step_rows,
        frame_index = 1,
        frame = nil,
        row = 0,
        prev = nil,
        saved = nil,
        saved_size = 0,
        index_size = 0,
        indices = nil,
        row_map = nil,
        prefix = ffi.new('int16_t[4096]'),
        suffix = ffi.new('uint8_t[4096]'),
        first = ffi.new('uint8_t[4096]'),
        tail = ffi.new('uint8_t[4096]'),
        l_bitbuf = 0,
        l_bitcnt = 0,
        l_code_size = 0,
        l_next_code = 0,
        l_old_code = nil,
        l_pending_len = 0,
        l_pending_pos = 1,
        l_block_pos = 0,
        l_block_remaining = 0,
        l_stream_end = false,
        l_ended = false,
        finished = false,
    }, Decoder)
    return decoder
end

function Decoder:read_code()
    local bits = self.l_code_size
    local bitbuf, bitcnt = self.l_bitbuf, self.l_bitcnt
    local bytes = self.bytes

    while bitcnt < bits do
        local remaining = self.l_block_remaining
        if remaining == 0 then
            if self.l_stream_end then
                self.l_ended = true
                return nil
            end
            if self.l_block_pos > self.data_len then
                fail('truncated LZW data')
            end
            local size = bytes[self.l_block_pos - 1]
            self.l_block_pos = self.l_block_pos + 1
            if size == 0 then
                self.l_stream_end = true
                return nil
            end
            remaining = size
        end

        if self.l_block_pos > self.data_len then
            fail('truncated LZW block')
        end
        local value = bytes[self.l_block_pos - 1]
        self.l_block_pos = self.l_block_pos + 1
        self.l_block_remaining = remaining - 1
        bitbuf = bitbuf + value * 2 ^ bitcnt
        bitcnt = bitcnt + 8
    end

    local size = 2 ^ bits
    local code = bitbuf % size
    self.l_bitbuf = (bitbuf - code) / size
    self.l_bitcnt = bitcnt - bits
    return code
end

function Decoder:fill_indices(target, need)
    local indices = self.indices
    local tail = self.tail
    local prefix, suffix, first = self.prefix, self.suffix, self.first
    local filled = 0

    while filled < need do
        local avail = self.l_pending_len - self.l_pending_pos + 1
        if avail > 0 then
            local take = avail
            if take > need - filled then
                take = need - filled
            end
            ffi.copy(indices + target + filled, tail + self.l_pending_pos - 1, take)
            self.l_pending_pos = self.l_pending_pos + take
            filled = filled + take
        else
            local code = self:read_code()
            if code == nil then
                break
            end

            if code == self.l_clear then
                self.l_code_size = self.l_min_code + 1
                self.l_next_code = self.l_eoi + 1
                self.l_old_code = nil
            elseif code == self.l_eoi then
                self.l_ended = true
                break
            elseif code > 4095 then
                fail('bad LZW code %d', code)
            elseif self.l_old_code == nil then
                if code >= self.l_next_code then
                    fail('bad first LZW code %d', code)
                end
                indices[target + filled] = suffix[code]
                filled = filled + 1
                self.l_old_code = code
            else
                local old = self.l_old_code
                local extra = 0
                local base_code = code
                local first_char
                if code == self.l_next_code then
                    extra = 1
                    base_code = old
                    first_char = first[old]
                elseif code < self.l_next_code then
                    first_char = first[code]
                else
                    fail('bad LZW code %d (next %d)', code, self.l_next_code)
                end

                local length = extra
                local current = base_code
                while current >= 0 do
                    length = length + 1
                    if length > 4097 then
                        fail('cyclic LZW table')
                    end
                    current = prefix[current]
                end

                local take = need - filled
                if take > length then
                    take = length
                end
                local tail_len = length - take

                local pos = length - 1
                if extra == 1 then
                    if pos < take then
                        indices[target + filled + pos] = first_char
                    else
                        tail[pos - take] = first_char
                    end
                    pos = pos - 1
                end

                current = base_code
                while current >= 0 do
                    local value = suffix[current]
                    if pos < take then
                        indices[target + filled + pos] = value
                    else
                        tail[pos - take] = value
                    end
                    pos = pos - 1
                    current = prefix[current]
                end

                filled = filled + take
                self.l_pending_len = tail_len
                self.l_pending_pos = 1

                if self.l_next_code < 4096 then
                    local next_code = self.l_next_code
                    prefix[next_code] = old
                    suffix[next_code] = first_char
                    first[next_code] = first[old]
                    self.l_next_code = next_code + 1
                    if self.l_next_code == 2 ^ self.l_code_size and self.l_code_size < 12 then
                        self.l_code_size = self.l_code_size + 1
                    end
                end
                self.l_old_code = code
            end
        end
    end
    return filled
end

function Decoder:begin_frame()
    local frame = self.frames[self.frame_index]
    self.frame = frame
    self.row = 0

    local x0 = math.min(frame.x, self.width)
    local y0 = math.min(frame.y, self.height)
    local x1 = math.min(frame.x + frame.w, self.width)
    local y1 = math.min(frame.y + frame.h, self.height)
    self.rect = {
        x = x0,
        y = y0,
        w = math.max(0, x1 - x0),
        h = math.max(0, y1 - y0),
    }

    local pixels = frame.w * frame.h
    if self.index_size < pixels then
        self.indices = ffi.new('uint8_t[?]', pixels)
        self.index_size = pixels
    end

    self.row_map = nil
    self.row_map_inv = nil
    if frame.interlaced then
        local map = {}
        local inverse = {}
        local index = 0
        local starts = { 0, 4, 2, 1 }
        local steps = { 8, 8, 4, 2 }
        for pass = 1, 4 do
            local y = starts[pass]
            while y < frame.h do
                index = index + 1
                map[index] = y
                inverse[y] = index - 1
                y = y + steps[pass]
            end
        end
        self.row_map = map
        self.row_map_inv = inverse
    end

    self.l_block_pos = frame.data_start
    self.l_block_remaining = 0
    self.l_stream_end = false
    self.l_bitbuf = 0
    self.l_bitcnt = 0
    self.l_min_code = frame.min_code
    self.l_clear = 2 ^ frame.min_code
    self.l_eoi = self.l_clear + 1
    self.l_code_size = frame.min_code + 1
    self.l_next_code = self.l_eoi + 1
    self.l_old_code = nil
    self.l_pending_len = 0
    self.l_pending_pos = 1
    self.l_ended = false

    for code = 0, self.l_clear - 1 do
        self.prefix[code] = -1
        self.suffix[code] = code
        self.first[code] = code
    end
end

function Decoder:save_rect()
    local rect = self.rect
    local size = rect.w * rect.h * 4
    if self.saved_size < size then
        self.saved = ffi.new('uint8_t[?]', size)
        self.saved_size = size
    end
    local canvas = ffi.cast('uint8_t*', self.canvas)
    local saved = ffi.cast('uint8_t*', self.saved)
    local row_bytes = rect.w * 4
    for y = 0, rect.h - 1 do
        local source = ((rect.y + y) * self.width + rect.x) * 4
        ffi.copy(saved + y * row_bytes, canvas + source, row_bytes)
    end
end

function Decoder:restore_rect(rect)
    local canvas = ffi.cast('uint8_t*', self.canvas)
    local saved = ffi.cast('uint8_t*', self.saved)
    local row_bytes = rect.w * 4
    for y = 0, rect.h - 1 do
        local target = ((rect.y + y) * self.width + rect.x) * 4
        ffi.copy(canvas + target, saved + y * row_bytes, row_bytes)
    end
end

function Decoder:apply_disposal()
    local prev = self.prev
    if prev == nil or prev.rect.w == 0 or prev.rect.h == 0 then
        return
    end
    if prev.disposal == 2 then
        local canvas = ffi.cast('uint8_t*', self.canvas)
        local row_bytes = prev.rect.w * 4
        for y = 0, prev.rect.h - 1 do
            local offset = ((prev.rect.y + y) * self.width + prev.rect.x) * 4
            ffi.fill(canvas + offset, row_bytes, 0)
        end
    elseif prev.disposal == 3 then
        self:restore_rect(prev.rect)
    end
end

function Decoder:draw_indices_scaled()
    local frame = self.frame
    local indices = self.indices
    local palette = frame.palette
    local palette_size = #palette
    local transparent = frame.transparent
    local width = self.width
    local x_map, y_map = self.x_map, self.y_map
    local row_map = frame.interlaced and self.row_map_inv or nil
    local canvas = ffi.cast('uint8_t*', self.canvas)
    local cell_width, cell_height = self.cell_width, self.cell_height
    local frame_x, frame_y = frame.x, frame.y
    local frame_w, frame_h = frame.w, frame.h

    for dy = 0, cell_height - 1 do
        local canvas_y = y_map[dy]
        local local_y = canvas_y - frame_y
        if local_y >= 0 and local_y < frame_h then
            local source_y = local_y
            if row_map ~= nil then
                source_y = row_map[local_y]
            end
            if source_y ~= nil then
                local source_row = source_y * frame_w
                local target_row = canvas_y * width
                for dx = 0, cell_width - 1 do
                    local canvas_x = x_map[dx]
                    local local_x = canvas_x - frame_x
                    if local_x >= 0 and local_x < frame_w then
                        local color = indices[source_row + local_x]
                        if color ~= transparent then
                            local palette_offset = color * 3
                            if palette_offset + 2 < palette_size then
                                local offset = (target_row + canvas_x) * 4
                                canvas[offset] = palette[palette_offset + 1]
                                canvas[offset + 1] = palette[palette_offset + 2]
                                canvas[offset + 2] = palette[palette_offset + 3]
                                canvas[offset + 3] = 255
                            end
                        end
                    end
                end
            end
        end
    end
end

function Decoder:draw_indices()
    local rect, frame = self.rect, self.frame
    if rect.w == 0 or rect.h == 0 then
        return
    end
    if self.scale < 1 then
        self:draw_indices_scaled()
        return
    end

    local canvas = ffi.cast('uint8_t*', self.canvas)
    local indices = self.indices
    local palette = frame.palette
    local palette_size = #palette
    local transparent = frame.transparent
    local width = self.width
    local height = self.height

    for source_y = 0, frame.h - 1 do
        local target_y
        if frame.interlaced then
            target_y = self.row_map[source_y + 1]
        else
            target_y = source_y
        end
        local canvas_y = rect.y + target_y
        if canvas_y < height then
            local source_row = source_y * frame.w
            local target_row = (canvas_y * width + rect.x) * 4
            for x = 0, rect.w - 1 do
                local color = indices[source_row + x]
                if color ~= transparent then
                    local palette_offset = color * 3
                    if palette_offset + 2 < palette_size then
                        local offset = target_row + x * 4
                        canvas[offset] = palette[palette_offset + 1]
                        canvas[offset + 1] = palette[palette_offset + 2]
                        canvas[offset + 2] = palette[palette_offset + 3]
                        canvas[offset + 3] = 255
                    end
                end
            end
        end
    end
end

function Decoder:copy_to_atlas(cell)
    local canvas = ffi.cast('uint8_t*', self.canvas)
    local atlas = ffi.cast('uint8_t*', self.atlas)
    local col = (cell - 1) % self.cols
    local row = math.floor((cell - 1) / self.cols)
    local cell_width = self.cell_width
    local cell_height = self.cell_height
    local width = self.width

    if cell_width == width and cell_height == self.height then
        local row_bytes = width * 4
        local atlas_row_bytes = self.atlas_width * 4
        for y = 0, self.height - 1 do
            local source = y * row_bytes
            local target = (row * self.height + y) * atlas_row_bytes + col * row_bytes
            ffi.copy(atlas + target, canvas + source, row_bytes)
        end
        return
    end

    local x_map, y_map = self.x_map, self.y_map
    local atlas_row_bytes = self.atlas_width * 4
    for y = 0, cell_height - 1 do
        local source_row = y_map[y] * width
        local target_row = (row * cell_height + y) * atlas_row_bytes + col * cell_width * 4
        for x = 0, cell_width - 1 do
            local source = (source_row + x_map[x]) * 4
            local target = target_row + x * 4
            atlas[target] = canvas[source]
            atlas[target + 1] = canvas[source + 1]
            atlas[target + 2] = canvas[source + 2]
            atlas[target + 3] = canvas[source + 3]
        end
    end
end

function Decoder:finish_frame()
    local frame = self.frame
    self:apply_disposal()
    if self.rect.w > 0 and self.rect.h > 0 and frame.disposal == 3 then
        self:save_rect()
    end
    self:draw_indices()
    self:copy_to_atlas(self.frame_index)
    self.prev = { rect = self.rect, disposal = frame.disposal }
    self.frame = nil
    self.frame_index = self.frame_index + 1
end

local function step_raw(decoder, rows)
    if decoder.finished then
        return 'done'
    end
    if decoder.frame_index > decoder.frame_count then
        decoder.finished = true
        return 'done'
    end
    if decoder.frame == nil then
        decoder:begin_frame()
    end

    rows = rows or decoder.step_rows
    if type(rows) ~= 'number' or rows < 1 then
        rows = 1
    end

    local frame = decoder.frame
    local processed = 0
    while processed < rows and decoder.row < frame.h do
        local base = decoder.row * frame.w
        local filled = decoder:fill_indices(base, frame.w)
        if filled < frame.w then
            local pad = frame.transparent or 0
            local from = base + filled
            local count = frame.w * frame.h - from
            if count > 0 then
                ffi.fill(decoder.indices + from, count, pad)
            end
            decoder.row = frame.h
        else
            decoder.row = decoder.row + 1
            processed = processed + 1
        end
    end

    if decoder.row >= frame.h then
        decoder:finish_frame()
        return 'frame'
    end
    return 'more'
end

function Decoder:step(rows)
    local ok, status, err = pcall(step_raw, self, rows)
    if not ok then
        return nil, clean(status)
    end
    return status, err
end

function Decoder:result()
    local frames = {}
    for index, frame in ipairs(self.frames) do
        frames[index] = {
            delay = delay_ms(frame.delay_cs),
            disposal = frame.disposal,
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h,
        }
    end
    return {
        width = self.width,
        height = self.height,
        atlas_width = self.atlas_width,
        atlas_height = self.atlas_height,
        atlas_pixels = self.atlas_pixels,
        size = self.atlas_pixels * 4,
        cell_width = self.cell_width,
        cell_height = self.cell_height,
        scale = self.scale,
        cols = self.cols,
        rows = self.rows,
        frame_count = self.frame_count,
        loop_count = self.loop_count,
        frames = frames,
        data = self.atlas,
    }
end

function Decoder:run()
    while true do
        local status, err = self:step(self.step_rows)
        if status == nil then
            return nil, err
        end
        if status == 'done' then
            return self:result()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Encoders
-- ---------------------------------------------------------------------------

local function check_atlas(atlas)
    if type(atlas) ~= 'table' or atlas.data == nil then
        fail('atlas is missing pixel data')
    end
    if type(atlas.atlas_width) ~= 'number' or type(atlas.atlas_height) ~= 'number' then
        fail('atlas is missing dimensions')
    end
end

function M.encode_bmp(atlas)
    check_atlas(atlas)
    local width, height = atlas.atlas_width, atlas.atlas_height
    local pixel_bytes = width * height * 4
    local size = 54 + pixel_bytes
    local out = ffi.new('uint8_t[?]', size)
    local header = 'BM' .. u32le(size) .. u16le(0) .. u16le(0) .. u32le(54)
        .. u32le(40) .. u32le(width) .. u32le(height) .. u16le(1) .. u16le(32)
        .. u32le(0) .. u32le(pixel_bytes) .. u32le(0) .. u32le(0)
        .. u32le(0) .. u32le(0)
    ffi.copy(out, header, 54)

    local source = ffi.cast('uint8_t*', atlas.data)
    local offset = 54
    local row_bytes = width * 4
    for y = height - 1, 0, -1 do
        local row = y * row_bytes
        for x = 0, width - 1 do
            local pixel = row + x * 4
            out[offset] = source[pixel + 2]
            out[offset + 1] = source[pixel + 1]
            out[offset + 2] = source[pixel]
            out[offset + 3] = source[pixel + 3]
            offset = offset + 4
        end
    end
    return out, size
end

function M.encode_tga(atlas)
    check_atlas(atlas)
    local width, height = atlas.atlas_width, atlas.atlas_height
    local size = 18 + width * height * 4
    local out = ffi.new('uint8_t[?]', size)
    local header = string.char(
        0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        width % 256, math.floor(width / 256) % 256,
        height % 256, math.floor(height / 256) % 256,
        32, 0x28)
    ffi.copy(out, header, 18)

    local source = ffi.cast('uint8_t*', atlas.data)
    local offset = 18
    for y = 0, height - 1 do
        local row = y * width * 4
        for x = 0, width - 1 do
            local pixel = row + x * 4
            out[offset] = source[pixel + 2]
            out[offset + 1] = source[pixel + 1]
            out[offset + 2] = source[pixel]
            out[offset + 3] = source[pixel + 3]
            offset = offset + 4
        end
    end
    return out, size
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

local function prepare(data, opts)
    local options = make_opts(opts)
    local ok, info = pcall(parse_raw, data, options)
    if not ok then
        return nil, nil, nil, clean(info)
    end
    local plan, err = plan_atlas(info, options)
    if plan == nil then
        return nil, nil, nil, err
    end
    return info, plan, options
end

function M.info(data)
    local ok, info = pcall(parse_raw, data, make_opts(nil))
    if not ok then
        return nil, clean(info)
    end
    local delays = {}
    for index, frame in ipairs(info.frames) do
        delays[index] = delay_ms(frame.delay_cs)
    end
    return {
        width = info.width,
        height = info.height,
        frame_count = #info.frames,
        loop_count = info.loop_count,
        delays = delays,
    }
end

function M.decoder(data, opts)
    local info, plan, options, err = prepare(data, opts)
    if info == nil then
        return nil, err
    end
    return make_decoder(data, info, plan, options)
end

function M.decode(data, opts)
    local decoder, err = M.decoder(data, opts)
    if decoder == nil then
        return nil, err
    end
    local ok, result, run_err = pcall(function()
        return decoder:run()
    end)
    if not ok then
        return nil, clean(result)
    end
    if result == nil then
        return nil, run_err
    end
    return result
end

function M.first_frame(data, opts)
    local merged = {}
    if type(opts) == 'table' then
        for key, value in pairs(opts) do
            merged[key] = value
        end
    end
    merged.limit_frames = 1
    local decoder, err = M.decoder(data, merged)
    if decoder == nil then
        return nil, err
    end
    local ok, result, run_err = pcall(function()
        return decoder:run()
    end)
    if not ok then
        return nil, clean(result)
    end
    if result == nil then
        return nil, run_err
    end
    result.frame_count = 1
    return result
end

return M
