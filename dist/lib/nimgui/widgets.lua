-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

local ffi = require 'ffi'
local color = require 'color'
local motion = require 'motion'
local imgui = require 'mimgui'
local theme = require 'nimgui.theme'
local state_mod = require 'nimgui.state'

local M = {}

local DISABLED_ALPHA = 0.45
local TOAST_IN, TOAST_HOLD, TOAST_OUT = 0.18, 2.2, 0.25
local TOAST_MARGIN = 16

local binders = setmetatable({}, { __mode = 'k' })
local text_fields = setmetatable({}, { __mode = 'k' })
local hidden_labels = {}
local segment_ids = {}
local modal_open = {}

local segment_tracker = motion.tracker(0.08)
local toggle_tracker = motion.tracker(0.07)
local progress_tracker = motion.tracker(0.12)

local active_toast = nil
local toast_flags = nil

local function raw_state(state)
    if type(state) ~= 'table' then
        error('nimgui.widgets: state must be a table or a nimgui.state binder', 3)
    end
    if type(state.bool) == 'function' then
        return state.state
    end
    return state
end

local function bindings(state)
    local raw = raw_state(state)
    local binder = binders[raw]
    if binder == nil then
        binder = state_mod.create(raw)
        binders[raw] = binder
    end
    return binder, raw
end

local function hidden_label(key)
    local id = hidden_labels[key]
    if id == nil then
        id = '##' .. tostring(key)
        hidden_labels[key] = id
    end
    return id
end

function M.frame_dt()
    local ok, io = pcall(imgui.GetIO)
    if ok and io then
        local dt = tonumber(io.DeltaTime)
        if dt and dt > 0 then
            return math.min(dt, 0.1)
        end
    end
    return 0.016
end

local function frame_step(t, dt)
    if t.reduce_motion then
        return math.huge
    end
    return dt or M.frame_dt()
end

local function push_frame_colors(t)
    imgui.PushStyleColorU32(imgui.Col.FrameBg, t.color.raised)
    imgui.PushStyleColorU32(imgui.Col.FrameBgHovered, t.color.raisedHover)
    imgui.PushStyleColorU32(imgui.Col.FrameBgActive, t.color.raisedActive)
end

-- Native ImGui frames default to font height + 2 * FramePadding.y, which is
-- below the 44*S touch target. Grow the vertical padding for one control.
local function push_touch_frame(t)
    local font = imgui.GetFontSize and imgui.GetFontSize() or 14 * t.scale
    local pad = (t.control_h - font) / 2
    if pad < t.sp('sm') then
        pad = t.sp('sm')
    end
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(t.sp('sm'), pad))
end

local function field_label(label, t)
    if label == nil or label == '' then
        return
    end
    imgui.PushStyleColorU32(imgui.Col.Text, t.color.muted)
    imgui.TextUnformatted(label)
    imgui.PopStyleColor(1)
end

local function role_colors(t, role)
    local raw = t.raw
    if role == 'primary' then
        return t.color.accent, color.rgb(raw.accentHover), color.rgb(raw.accentActive), t.color.onAccent
    elseif role == 'danger' then
        return t.color.danger,
            color.rgb(color.mix(raw.danger, 0xFFFFFF, 0.12)),
            color.rgb(color.mix(raw.danger, 0x000000, 0.15)),
            color.rgb(color.readable_on(raw.danger))
    elseif role == 'ghost' then
        return color.rgb(raw.bg, 0), t.color.raisedHover, t.color.raisedActive, t.color.text
    elseif role == 'secondary' then
        return t.color.raised, t.color.raisedHover, t.color.raisedActive, t.color.text
    end
    error('nimgui.widgets.button: unknown role "' .. tostring(role) .. '"', 3)
end

function M.button(role, label, opts)
    if type(label) ~= 'string' or label == '' then
        error('nimgui.widgets.button: label must be a non-empty string', 2)
    end
    opts = opts or {}
    local t = opts.theme or theme.active()
    local base, hover, active, text = role_colors(t, role)
    local disabled = opts.disabled and true or false

    local width = opts.width
    if width == nil or width < 0 then
        width = imgui.GetContentRegionAvail().x
    end
    local height = opts.height or t.control_h

    imgui.PushStyleColorU32(imgui.Col.Button, base)
    imgui.PushStyleColorU32(imgui.Col.ButtonHovered, disabled and base or hover)
    imgui.PushStyleColorU32(imgui.Col.ButtonActive, disabled and base or active)
    imgui.PushStyleColorU32(imgui.Col.Text, disabled and t.color.muted or text)
    if disabled then
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, DISABLED_ALPHA)
    end

    local pressed = imgui.Button(label, imgui.ImVec2(width, height))
    local hovered = disabled and opts.disabled_hint ~= nil and imgui.IsItemHovered()

    if disabled then
        imgui.PopStyleVar(1)
        pressed = false
    end
    imgui.PopStyleColor(4)

    if hovered then
        M.tooltip(opts.disabled_hint)
    end
    return pressed
end

local function segment_id(key, index)
    local ids = segment_ids[key]
    if ids == nil then
        ids = {}
        segment_ids[key] = ids
    end
    local id = ids[index]
    if id == nil then
        id = tostring(key) .. '#' .. index
        ids[index] = id
    end
    return id
end

function M.segmented(items, state, key, dt)
    if type(items) ~= 'table' or #items == 0 then
        error('nimgui.widgets.segmented: items must be a non-empty table', 2)
    end
    local raw = raw_state(state)
    local t = theme.active()
    local stored = raw[key]
    local current = stored
    if type(current) ~= 'number' or current < 1 or current > #items then
        current = 1
    end

    local avail = imgui.GetContentRegionAvail().x
    local gap = t.sp('sm')
    local width = (avail - gap * (#items - 1)) / #items
    if width < 1 then
        width = 1
    end

    local picked = current
    local step = frame_step(t, dt)
    local palette = t.raw

    for i = 1, #items do
        if i > 1 then
            imgui.SameLine(0, gap)
        end
        local item = items[i]
        local label = type(item) == 'table' and item.label or tostring(item)
        local mix = segment_tracker:step(segment_id(key, i), i == current and 1 or 0, step)
        local hover_raw = color.mix(palette.raisedHover, palette.accentHover, mix)
        local active_raw = color.mix(palette.raisedActive, palette.accentActive, mix)
        local text_raw = color.mix(palette.text, palette.onAccent, mix)

        imgui.PushStyleColorU32(imgui.Col.Button, color.rgb(color.mix(palette.raised, palette.accent, mix)))
        imgui.PushStyleColorU32(imgui.Col.ButtonHovered, color.rgb(hover_raw))
        imgui.PushStyleColorU32(imgui.Col.ButtonActive, color.rgb(active_raw))
        imgui.PushStyleColorU32(imgui.Col.Text, color.rgb(text_raw))
        if imgui.Button(label, imgui.ImVec2(width, t.control_h)) then
            picked = i
        end
        imgui.PopStyleColor(4)
    end

    if picked ~= stored then
        raw[key] = picked
    end
    return picked
end

local function has_draw_list()
    if imgui.GetWindowDrawList == nil
        or imgui.InvisibleButton == nil
        or imgui.GetCursorScreenPos == nil then
        return false
    end
    return imgui.GetWindowDrawList() ~= nil
end

function M.toggle(id, state, key, dt)
    if type(id) ~= 'string' or id == '' then
        error('nimgui.widgets.toggle: id must be a non-empty string', 2)
    end
    local binder, raw = bindings(state)
    local proxy = binder:bool(key)
    local t = theme.active()
    if raw[key] ~= nil then proxy:refresh() end
    local on = proxy:value()

    if not has_draw_list() then
        imgui.PushStyleColorU32(imgui.Col.FrameBg, t.color.raised)
        imgui.PushStyleColorU32(imgui.Col.CheckMark, t.color.accent)
        local changed = imgui.Checkbox(id, proxy:cdata())
        imgui.PopStyleColor(2)
        if changed then
            on = proxy:cdata()[0]
            raw[key] = on
        end
        return on
    end

    local scale = t.scale
    local hit_w = 48 * scale
    local hit_h = t.control_h
    local track_w, track_h = 44 * scale, 24 * scale
    local pos = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton(id, imgui.ImVec2(hit_w, hit_h))

    local mix = toggle_tracker:step(id, on and 1 or 0, frame_step(t, dt))
    local top = pos.y + (hit_h - track_h) / 2
    local dl = imgui.GetWindowDrawList()
    dl:AddRectFilled(
        imgui.ImVec2(pos.x, top),
        imgui.ImVec2(pos.x + track_w, top + track_h),
        color.rgb(color.mix(t.raw.raisedActive, t.raw.accent, mix)),
        track_h / 2)
    local radius = track_h / 2 - 3 * scale
    local knob_x = pos.x + track_h / 2 + (track_w - track_h) * mix
    dl:AddCircleFilled(imgui.ImVec2(knob_x, top + track_h / 2), radius, t.color.text, 20)

    if clicked then
        on = not on
        proxy:cdata()[0] = on
        raw[key] = on
    end
    return on
end

function M.checkbox(label, state, key)
    if type(label) ~= 'string' or label == '' then
        error('nimgui.widgets.checkbox: label must be a non-empty string', 2)
    end
    local binder, raw = bindings(state)
    local proxy = binder:bool(key)
    local t = theme.active()
    if raw[key] ~= nil then proxy:refresh() end

    push_frame_colors(t)
    imgui.PushStyleColorU32(imgui.Col.CheckMark, t.color.accent)
    push_touch_frame(t)
    local changed = imgui.Checkbox(label, proxy:cdata())
    imgui.PopStyleVar(1)
    imgui.PopStyleColor(4)

    local value = raw[key]
    if changed then
        value = proxy:cdata()[0]
        raw[key] = value
    end
    if value == nil then
        value = proxy:value()
    end
    return value
end

function M.slider(label, state, key, min, max)
    if type(label) ~= 'string' or label == '' then
        error('nimgui.widgets.slider: label must be a non-empty string', 2)
    end
    if type(min) ~= 'number' or type(max) ~= 'number' then
        error('nimgui.widgets.slider: min and max must be numbers', 2)
    end
    local binder, raw = bindings(state)
    local proxy = binder:float(key)
    local t = theme.active()
    if raw[key] ~= nil then proxy:refresh() end

    field_label(label, t)
    imgui.SetNextItemWidth(-1)
    push_frame_colors(t)
    imgui.PushStyleColorU32(imgui.Col.SliderGrab, t.color.accent)
    imgui.PushStyleColorU32(imgui.Col.SliderGrabActive, color.rgb(t.raw.accentActive))
    push_touch_frame(t)
    local changed = imgui.SliderFloat(hidden_label(key), proxy:cdata(), min, max, '%.2f')
    imgui.PopStyleVar(1)
    imgui.PopStyleColor(5)

    local value = raw[key]
    if changed then
        value = proxy:value()
        raw[key] = value
    end
    if value == nil then
        value = proxy:value()
    end
    return value
end

function M.input_int(label, state, key, step, step_fast)
    if type(label) ~= 'string' or label == '' then
        error('nimgui.widgets.input_int: label must be a non-empty string', 2)
    end
    local binder, raw = bindings(state)
    local proxy = binder:int(key)
    local t = theme.active()
    if raw[key] ~= nil then proxy:refresh() end

    field_label(label, t)
    imgui.SetNextItemWidth(-1)
    push_frame_colors(t)
    push_touch_frame(t)
    local changed = imgui.InputInt(hidden_label(key), proxy:cdata(), step or 1, step_fast or 100)
    imgui.PopStyleVar(1)
    imgui.PopStyleColor(3)

    local value = raw[key]
    if changed then
        value = proxy:value()
        raw[key] = value
    end
    if value == nil then
        value = proxy:value()
    end
    return value
end

function M.input_float(label, state, key, step, step_fast)
    if type(label) ~= 'string' or label == '' then
        error('nimgui.widgets.input_float: label must be a non-empty string', 2)
    end
    local binder, raw = bindings(state)
    local proxy = binder:float(key)
    local t = theme.active()
    if raw[key] ~= nil then proxy:refresh() end

    field_label(label, t)
    imgui.SetNextItemWidth(-1)
    push_frame_colors(t)
    push_touch_frame(t)
    local changed = imgui.InputFloat(hidden_label(key), proxy:cdata(), step or 0.1, step_fast or 1.0, '%.3f')
    imgui.PopStyleVar(1)
    imgui.PopStyleColor(3)

    local value = raw[key]
    if changed then
        value = proxy:value()
        raw[key] = value
    end
    if value == nil then
        value = proxy:value()
    end
    return value
end

local function text_field(raw, key, max_len)
    local fields = text_fields[raw]
    if fields == nil then
        fields = {}
        text_fields[raw] = fields
    end
    local field = fields[key]
    local size = max_len + 1
    if field == nil then
        field = { buf = ffi.new('char[?]', size), size = size, value = nil }
        fields[key] = field
    elseif size > field.size then
        field.buf = ffi.new('char[?]', size)
        field.size = size
        field.value = nil
    end
    return field
end

function M.input_text(label, state, key, max_len)
    if type(label) ~= 'string' or label == '' then
        error('nimgui.widgets.input_text: label must be a non-empty string', 2)
    end
    max_len = max_len or 64
    if type(max_len) ~= 'number' or max_len < 1 then
        error('nimgui.widgets.input_text: max_len must be a positive number', 2)
    end
    local raw = raw_state(state)
    local t = theme.active()
    local field = text_field(raw, key, max_len)

    local value = raw[key]
    if value == nil then
        value = ''
    end
    if type(value) ~= 'string' then
        value = tostring(value)
    end
    if field.value ~= value then
        local length = #value
        if length > max_len then
            length = max_len
        end
        ffi.copy(field.buf, value, length)
        field.buf[length] = 0
        field.value = value
    end

    field_label(label, t)
    imgui.SetNextItemWidth(-1)
    push_frame_colors(t)
    push_touch_frame(t)
    local changed = imgui.InputText(hidden_label(key), field.buf, field.size)
    imgui.PopStyleVar(1)
    imgui.PopStyleColor(3)

    if changed then
        local text = ffi.string(field.buf)
        field.value = text
        raw[key] = text
    end
    return raw[key] or field.value or ''
end

function M.stat_tile(label, value, opts)
    opts = opts or {}
    local t = opts.theme or theme.active()
    local width = opts.width
    if width == nil or width < 0 then
        width = imgui.GetContentRegionAvail().x
    end
    local height = opts.height or 64 * t.scale
    local id = opts.id or label
    local border = opts.border ~= false

    imgui.PushStyleColorU32(imgui.Col.ChildBg, t.color.surface)
    imgui.PushStyleColorU32(imgui.Col.Border, t.color.border)
    local visible = imgui.BeginChild(id, imgui.ImVec2(width, height), border)
    if visible then
        imgui.PushStyleColorU32(imgui.Col.Text, t.color.muted)
        imgui.TextUnformatted(label)
        imgui.PopStyleColor(1)
        imgui.TextUnformatted(tostring(value))
    end
    imgui.EndChild()
    imgui.PopStyleColor(2)
end

function M.progress(value, opts)
    opts = opts or {}
    local t = opts.theme or theme.active()
    local fraction = tonumber(value) or 0
    if fraction < 0 then
        fraction = 0
    elseif fraction > 1 then
        fraction = 1
    end

    if opts.smooth then
        local id = opts.id or '##nimgui_progress'
        fraction = motion.clamp01(progress_tracker:step(id, fraction, frame_step(t, opts.dt)))
    end

    local width = opts.width
    if width == nil or width < 0 then
        width = -1
    end
    local height = opts.height or 6 * t.scale

    imgui.PushStyleColorU32(imgui.Col.PlotHistogram, opts.color or t.color.accent)
    imgui.PushStyleColorU32(imgui.Col.FrameBg, t.color.raised)
    imgui.ProgressBar(fraction, imgui.ImVec2(width, height), opts.overlay or '')
    imgui.PopStyleColor(2)
    return fraction
end

function M.empty(title, hint, opts)
    opts = opts or {}
    local t = opts.theme or theme.active()

    imgui.Dummy(imgui.ImVec2(0, 24 * t.scale))
    imgui.PushStyleColorU32(imgui.Col.Text, t.color.text)
    imgui.TextUnformatted(title)
    imgui.PopStyleColor(1)
    if hint then
        imgui.PushStyleColorU32(imgui.Col.Text, t.color.muted)
        imgui.TextUnformatted(hint)
        imgui.PopStyleColor(1)
    end
    if opts.action then
        imgui.Dummy(imgui.ImVec2(0, t.sp('sm')))
        return M.button(opts.action_role or 'secondary', opts.action, {
            theme = t,
            width = opts.action_width,
        })
    end
    return false
end

function M.tooltip(text)
    if text == nil or text == '' then
        return
    end
    imgui.BeginTooltip()
    imgui.TextUnformatted(text)
    imgui.EndTooltip()
end

local modal_names = {}

local function modal_name(id, title)
    if title == nil or title == id then
        return id
    end
    local names = modal_names[id]
    if names == nil then
        names = {}
        modal_names[id] = names
    end
    local name = names[title]
    if name == nil then
        name = title .. '##' .. id
        names[title] = name
    end
    return name
end

function M.modal(id, title, draw_fn, opts)
    if type(id) ~= 'string' or id == '' then
        error('nimgui.widgets.modal: id must be a non-empty string', 2)
    end
    if type(draw_fn) ~= 'function' then
        error('nimgui.widgets.modal: draw_fn must be a function', 2)
    end
    opts = opts or {}
    local t = opts.theme or theme.active()
    local name = modal_name(id, title)
    local wants_open = opts.open and true or false

    if wants_open and not modal_open[id] then
        imgui.OpenPopup(name)
    end
    modal_open[id] = wants_open

    local is_open = imgui.BeginPopupModal(name, nil, opts.flags or 0)
    if is_open then
        draw_fn()
        if opts.close_label then
            if M.button('secondary', opts.close_label, { theme = t, width = opts.close_width }) then
                imgui.CloseCurrentPopup()
            end
        end
        imgui.EndPopup()
    end
    return is_open
end

function M.toast(text)
    if text == nil or text == '' then
        return
    end
    active_toast = { text = text, born = imgui.GetTime() }
end

function M.toast_active()
    return active_toast ~= nil
end

function M.toast_alpha(age, reduce)
    if reduce then
        return 1
    end
    if age < TOAST_IN then
        return motion.ease.out_cubic(age / TOAST_IN)
    end
    if age < TOAST_IN + TOAST_HOLD then
        return 1
    end
    return 1 - motion.clamp01((age - TOAST_IN - TOAST_HOLD) / TOAST_OUT)
end

local function toast_window_flags()
    if toast_flags == nil then
        local flags = imgui.WindowFlags
        toast_flags = flags.NoTitleBar
            + flags.NoResize
            + flags.AlwaysAutoResize
            + flags.NoMove
            + flags.NoSavedSettings
            + flags.NoMouseInputs
            + flags.NoNavInputs
    end
    return toast_flags
end

function M.draw_toast(theme_override)
    if active_toast == nil then
        return false
    end
    local t = theme_override or theme.active()
    local age = imgui.GetTime() - active_toast.born
    local total = t.reduce_motion and (TOAST_IN + TOAST_HOLD) or (TOAST_IN + TOAST_HOLD + TOAST_OUT)
    if age > total then
        active_toast = nil
        return false
    end

    local alpha = M.toast_alpha(age, t.reduce_motion)
    local margin = TOAST_MARGIN * t.scale
    local ok, screen_w = pcall(_G.getScreenResolution)
    if ok and type(screen_w) == 'number' then
        imgui.SetNextWindowPos(
            imgui.ImVec2(screen_w - margin, margin),
            imgui.Cond.Always,
            imgui.ImVec2(1, 0))
    end

    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, alpha)
    imgui.PushStyleColorU32(imgui.Col.WindowBg, t.color.surface)
    imgui.PushStyleColorU32(imgui.Col.Border, t.color.border)
    imgui.PushStyleColorU32(imgui.Col.Text, t.color.text)
    imgui.Begin('##nimgui_toast', nil, toast_window_flags())
    imgui.TextUnformatted(active_toast.text)
    imgui.End()
    imgui.PopStyleColor(3)
    imgui.PopStyleVar(1)
    return true
end

function M.reset()
    active_toast = nil
    modal_open = {}
    modal_names = {}
    segment_ids = {}
    segment_tracker = motion.tracker(0.08)
    toggle_tracker = motion.tracker(0.07)
    progress_tracker = motion.tracker(0.12)
    binders = setmetatable({}, { __mode = 'k' })
    text_fields = setmetatable({}, { __mode = 'k' })
end

return M
