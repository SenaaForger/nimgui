-- fake mimgui binding for nimgui headless tests

local ffi = require 'ffi'

local fake = {
    colorPush = 0,
    colorPop = 0,
    varPush = 0,
    varPop = 0,
    newCalls = 0,
    subs = {},
    inits = {},
    time = 1.0,
}

local function enum(names)
    local t = {}
    for i, name in ipairs(names) do
        t[name] = i
    end
    return t
end

fake.Col = enum({
    'WindowBg', 'ChildBg', 'TitleBg', 'TitleBgActive', 'Border', 'Text', 'TextDisabled',
    'Button', 'ButtonHovered', 'ButtonActive', 'FrameBg', 'FrameBgHovered', 'FrameBgActive',
    'CheckMark', 'SliderGrab', 'SliderGrabActive', 'Separator', 'Tab', 'TabActive', 'TabUnfocused',
    'Header', 'HeaderHovered', 'HeaderActive', 'PopupBg', 'PlotHistogram',
})

fake.StyleVar = enum({
    'Alpha', 'ChildRounding', 'FrameRounding', 'GrabRounding', 'ScrollbarRounding',
    'TabRounding', 'WindowRounding', 'WindowPadding', 'FramePadding', 'ItemSpacing',
})

fake.Cond = { Always = 1, Once = 2, FirstUseEver = 4, Appearing = 8 }
fake.WindowFlags = {
    NoTitleBar = 1, NoResize = 2, NoMove = 4, NoScrollbar = 8, NoScrollWithMouse = 16,
    NoCollapse = 32, AlwaysAutoResize = 64, NoBackground = 128, NoSavedSettings = 256,
    NoMouseInputs = 512, MenuBar = 1024, HorizontalScrollbar = 2048,
    NoFocusOnAppearing = 4096, NoBringToFrontOnFocus = 8192,
    AlwaysVerticalScrollbar = 16384, AlwaysHorizontalScrollbar = 32768,
    AlwaysUseWindowPadding = 65536, NoNavInputs = 262144, NoNavFocus = 524288,
}
fake.TabBarFlags = { None = 0, NoTooltip = 16 }
fake.TabItemFlags = { None = 0, SetSelected = 8 }

function fake.ImVec2(x, y) return { x = x, y = y } end
function fake.ImVec4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

fake.new = {
    int = function(value) fake.newCalls = fake.newCalls + 1 return { [0] = value or 0 } end,
    bool = function(value) fake.newCalls = fake.newCalls + 1 return { [0] = value and true or false } end,
    float = function(value) fake.newCalls = fake.newCalls + 1 return { [0] = value or 0 } end,
}

fake.fontAtlas = {
    fonts = {},
    built = false,
    TexID = nil,
}

function fake.fontAtlas:GetGlyphRangesCyrillic() return 'cyrillic' end
function fake.fontAtlas:GetGlyphRangesDefault() return 'default' end
function fake.fontAtlas:IsBuilt() return self.built end

local function add_font(kind, source, size, cfg, ranges)
    local entry = {
        kind = kind,
        source = source,
        size = size,
        cfg = cfg,
        ranges = ranges,
        index = #fake.fontAtlas.fonts + 1,
    }
    fake.fontAtlas.fonts[#fake.fontAtlas.fonts + 1] = entry
    return entry
end

function fake.fontAtlas:AddFontFromFileTTF(path, size, cfg, ranges)
    fake.count.fontAdds = fake.count.fontAdds + 1
    return add_font('file', path, size, cfg, ranges)
end

function fake.fontAtlas:AddFontFromMemoryCompressedBase85TTF(data, size, cfg, ranges)
    fake.count.fontAdds = fake.count.fontAdds + 1
    return add_font('base85', data, size, cfg, ranges)
end

local function reset_counts()
    fake.count = {
        Begin = 0, End = 0, BeginChild = 0, EndChild = 0,
        Dummy = 0, Spacing = 0, Separator = 0, SameLine = 0,
        Text = 0, Button = 0, Checkbox = 0, SliderFloat = 0,
        InputInt = 0, InputFloat = 0, InputText = 0,
        ProgressBar = 0, BeginPopupModal = 0, EndPopup = 0,
        OpenPopup = 0, ClosePopup = 0, BeginTooltip = 0, EndTooltip = 0,
        SetNextWindowPos = 0, SetNextWindowSize = 0,
        SetNextWindowSizeConstraints = 0, SetNextItemWidth = 0, InvisibleButton = 0,
        Image = 0, textureUploads = 0, textureReleases = 0,
        fontAdds = 0, fontPushes = 0, fontPops = 0, fontInvalidates = 0,
    }
    fake.last = {}
    fake.texts = {}
    fake.buttonQueue = {}
    fake.buttonIndex = 1
    fake.draw = { rects = {}, circles = {}, images = {}, texts = {} }
    fake.textures = {}
    fake.releasedTextures = {}
    fake.uploadFail = false
    fake.fontAtlas.fonts = {}
    fake.fontAtlas.built = false
    fake.fontAtlas.TexID = nil
    fake.pushedFonts = {}
    fake.glyphBuilders = {}
    fake.styleVarPushes = {}
    fake.fontSize = 14
    fake.beginResult = true
    fake.beginChildResult = true
    fake.modalResult = false
    fake.invisibleResult = false
    fake.checkboxChanged = false
    fake.checkboxValue = false
    fake.sliderChanged = false
    fake.sliderValue = 0
    fake.inputIntChanged = false
    fake.inputIntValue = 0
    fake.inputFloatChanged = false
    fake.inputFloatValue = 0
    fake.inputTextChanged = false
    fake.inputTextValue = ''
    fake.drawListEnabled = true
    fake.avail = { x = 320, y = 480 }
    fake.textWidthPerChar = 7
    fake.cursor = { x = 10, y = 20 }
end

reset_counts()

function fake.OnFrame(cond, before, draw)
    local sub = { Condition = cond, _before = before, _draw = draw, unsubscribed = false }
    function sub:Unsubscribe() self.unsubscribed = true end
    fake.subs[#fake.subs + 1] = sub
    return sub
end

function fake.OnInitialize(fn) fake.inits[#fake.inits + 1] = fn end

function fake.PushStyleColorU32() fake.colorPush = fake.colorPush + 1 end
function fake.PopStyleColor(count) fake.colorPop = fake.colorPop + (count or 1) end
function fake.PushStyleVarFloat() fake.varPush = fake.varPush + 1 end
function fake.PushStyleVarVec2(name, value)
    fake.varPush = fake.varPush + 1
    fake.styleVarPushes[#fake.styleVarPushes + 1] = { name = name, value = value }
end
function fake.PopStyleVar(count) fake.varPop = fake.varPop + (count or 1) end

fake.GetStyle = function() return { ScaleAllSizes = function() end } end
fake.GetFontSize = function() return fake.fontSize or 14 end
fake.io = { DeltaTime = 1 / 60, Fonts = fake.fontAtlas }
fake.GetIO = function()
    fake.io.DeltaTime = fake.delta or 1 / 60
    return fake.io
end
fake.GetTime = function() return fake.time end

local draw_list = {}

function draw_list:AddRectFilled(a, b, col, rounding)
    fake.draw.rects[#fake.draw.rects + 1] = { a = a, b = b, col = col, rounding = rounding }
end

function draw_list:AddRect(a, b, col, rounding)
    fake.draw.rects[#fake.draw.rects + 1] = { a = a, b = b, col = col, rounding = rounding, stroke = true }
end

function draw_list:AddCircleFilled(center, radius, col, segments)
    fake.draw.circles[#fake.draw.circles + 1] = { center = center, radius = radius, col = col, segments = segments }
end

function draw_list:AddImage(texture, a, b, uv0, uv1, tint)
    fake.draw.images[#fake.draw.images + 1] = {
        texture = texture, a = a, b = b, uv0 = uv0, uv1 = uv1, tint = tint,
    }
end

function draw_list:AddText(pos, col, text)
    fake.draw.texts[#fake.draw.texts + 1] = { pos = pos, col = col, text = text }
end

function fake.GetWindowDrawList()
    if not fake.drawListEnabled then return nil end
    return draw_list
end

fake.ImDrawList = { AddImage = function() end }

function fake.Begin(name, p_open, flags)
    fake.count.Begin = fake.count.Begin + 1
    fake.last.begin = { name = name, open = p_open, flags = flags }
    return fake.beginResult
end

function fake.End()
    fake.count.End = fake.count.End + 1
end

function fake.BeginChild(id, size, border, flags)
    fake.count.BeginChild = fake.count.BeginChild + 1
    fake.last.beginChild = { id = id, size = size, border = border, flags = flags }
    return fake.beginChildResult
end

function fake.EndChild()
    fake.count.EndChild = fake.count.EndChild + 1
end

function fake.Dummy(size)
    fake.count.Dummy = fake.count.Dummy + 1
    fake.last.dummy = size
end

function fake.Spacing()
    fake.count.Spacing = fake.count.Spacing + 1
end

function fake.Separator()
    fake.count.Separator = fake.count.Separator + 1
end

function fake.SameLine(offset, spacing)
    fake.count.SameLine = fake.count.SameLine + 1
    fake.last.sameLine = { offset = offset, spacing = spacing }
end

function fake.TextUnformatted(text)
    fake.count.Text = fake.count.Text + 1
    fake.texts[#fake.texts + 1] = text
end

function fake.GetContentRegionAvail()
    return { x = fake.avail.x, y = fake.avail.y }
end

function fake.SetNextItemWidth(width)
    fake.count.SetNextItemWidth = fake.count.SetNextItemWidth + 1
    fake.last.itemWidth = width
end

function fake.CalcTextSize(text)
    return { x = #text * fake.textWidthPerChar, y = 14 }
end

function fake.GetFrameHeight() return 32 end
function fake.GetTextLineHeight() return 14 end
function fake.GetCursorScreenPos() return fake.cursor end
function fake.IsItemHovered() return fake.itemHovered and true or false end

function fake.SetNextWindowPos(pos, cond, pivot)
    fake.count.SetNextWindowPos = fake.count.SetNextWindowPos + 1
    fake.last.windowPos = { pos = pos, cond = cond, pivot = pivot }
end

function fake.SetNextWindowSize(size, cond)
    fake.count.SetNextWindowSize = fake.count.SetNextWindowSize + 1
    fake.last.windowSize = { size = size, cond = cond }
end

function fake.SetNextWindowSizeConstraints(min, max)
    fake.count.SetNextWindowSizeConstraints = fake.count.SetNextWindowSizeConstraints + 1
    fake.last.constraints = { min = min, max = max }
end

function fake.InvisibleButton(id, size)
    fake.count.InvisibleButton = fake.count.InvisibleButton + 1
    fake.last.invisible = { id = id, size = size }
    return fake.invisibleResult
end

function fake.Button(label, size)
    fake.count.Button = fake.count.Button + 1
    fake.last.button = { label = label, size = size }
    local value = fake.buttonQueue[fake.buttonIndex]
    fake.buttonIndex = fake.buttonIndex + 1
    return value and true or false
end

function fake.Checkbox(label, v)
    fake.count.Checkbox = fake.count.Checkbox + 1
    fake.last.checkbox = label
    if fake.checkboxChanged then
        v[0] = fake.checkboxValue and true or false
        return true
    end
    return false
end

function fake.SliderFloat(label, v)
    fake.count.SliderFloat = fake.count.SliderFloat + 1
    fake.last.slider = label
    if fake.sliderChanged then
        v[0] = fake.sliderValue
        return true
    end
    return false
end

function fake.InputInt(label, v)
    fake.count.InputInt = fake.count.InputInt + 1
    fake.last.inputInt = label
    if fake.inputIntChanged then
        v[0] = fake.inputIntValue
        return true
    end
    return false
end

function fake.InputFloat(label, v)
    fake.count.InputFloat = fake.count.InputFloat + 1
    fake.last.inputFloat = label
    if fake.inputFloatChanged then
        v[0] = fake.inputFloatValue
        return true
    end
    return false
end

function fake.InputText(label, buf)
    fake.count.InputText = fake.count.InputText + 1
    fake.last.inputText = label
    if fake.inputTextChanged then
        ffi.copy(buf, fake.inputTextValue, #fake.inputTextValue)
        buf[#fake.inputTextValue] = 0
        return true
    end
    return false
end

function fake.ProgressBar(fraction, size, overlay)
    fake.count.ProgressBar = fake.count.ProgressBar + 1
    fake.last.progress = { fraction = fraction, size = size, overlay = overlay }
    return false
end

function fake.BeginPopupModal(name, p_open, flags)
    fake.count.BeginPopupModal = fake.count.BeginPopupModal + 1
    fake.last.popupModal = { name = name, flags = flags }
    return fake.modalResult
end

function fake.EndPopup()
    fake.count.EndPopup = fake.count.EndPopup + 1
end

function fake.OpenPopup(name)
    fake.count.OpenPopup = fake.count.OpenPopup + 1
    fake.last.openPopup = name
end

function fake.CloseCurrentPopup()
    fake.count.ClosePopup = fake.count.ClosePopup + 1
end

function fake.BeginTooltip()
    fake.count.BeginTooltip = fake.count.BeginTooltip + 1
end

function fake.EndTooltip()
    fake.count.EndTooltip = fake.count.EndTooltip + 1
end

fake.Combo = function() return false end
fake.Selectable = function() return false end
fake.StyleColorsDark = function() end
fake.StyleColorsLight = function() end

fake.CreateTextureFromFile = function() return nil end
function fake.CreateTextureFromFileInMemory(src, size)
    fake.count.textureUploads = fake.count.textureUploads + 1
    fake.last.upload = { src = src, size = size }
    if fake.uploadFail then
        return nil
    end
    local texture = ffi.new('uintptr_t[1]', fake.count.textureUploads)
    fake.textures[#fake.textures + 1] = texture
    return texture
end

function fake.ReleaseTexture(texture)
    fake.count.textureReleases = fake.count.textureReleases + 1
    fake.releasedTextures[#fake.releasedTextures + 1] = texture
end

function fake.Image(texture, size, uv0, uv1, tint, border)
    fake.count.Image = fake.count.Image + 1
    fake.last.image = {
        texture = texture, size = size, uv0 = uv0, uv1 = uv1, tint = tint, border = border,
    }
end
fake.CreateFontsTexture = function() end
function fake.InvalidateFontsTexture()
    fake.count.fontInvalidates = fake.count.fontInvalidates + 1
end

function fake.PushFont(font)
    fake.count.fontPushes = fake.count.fontPushes + 1
    fake.pushedFonts[#fake.pushedFonts + 1] = font
end

function fake.PopFont()
    fake.count.fontPops = fake.count.fontPops + 1
end

fake.ImFontConfig = function() return {} end
fake.ImVector_ImWchar = function() return {} end
fake.ImFontGlyphRangesBuilder = function()
    local builder = { ranges = {}, texts = {}, chars = {} }
    function builder:AddRanges(value) self.ranges[#self.ranges + 1] = value end
    function builder:AddText(value) self.texts[#self.texts + 1] = value end
    function builder:AddChar(value) self.chars[#self.chars + 1] = value end
    function builder:BuildRanges(vector)
        vector[0] = { Data = { builder = self } }
    end
    fake.glyphBuilders[#fake.glyphBuilders + 1] = builder
    return builder
end

function fake.reset()
    fake.colorPush, fake.colorPop = 0, 0
    fake.varPush, fake.varPop = 0, 0
    fake.newCalls = 0
    fake.subs = {}
    fake.inits = {}
    fake.time = 1.0
    fake.delta = nil
    fake.itemHovered = false
    reset_counts()
end

function fake.frame()
    for _, sub in ipairs(fake.subs) do
        if not sub.unsubscribed and sub.Condition() then
            if sub._before then sub._before(sub) end
            if sub._draw then sub._draw(sub) end
        end
    end
end

return fake
