-- MonetLoader for Android 3.8.0
-- nimgui reference script: theme, fonts, layout, widgets, and media.
-- Docs: README.md
-- Put an optional GIF named nimgui_demo.gif and a PNG/JPG named nimgui_demo.png
-- next to this script.

script_name('nimgui Demo')
script_version('1.0')
script_version_number(1)
script_author('Sena')
script_description('Contoh pemakaian library nimgui: panel, widget, font, dan media.')

local imgui = require 'mimgui'
local nimgui = require 'nimgui'

local GIF_FILE = 'nimgui_demo.gif'
local IMAGE_FILE = 'nimgui_demo.png'
local IMAGE_W, IMAGE_H = 512, 512

local open = false
local theme
local anim
local anim_error
local image
local image_error
local font_error

local cfg = {
    tab = 1,
    media = 1,
    enabled = true,
    volume = 0.6,
    channel = 1,
    ratio = 0.35,
    name = 'Sena',
}

local function draw_title(text)
    if nimgui.fonts.push('display') then
        imgui.TextUnformatted(text)
        nimgui.fonts.pop()
    else
        imgui.TextUnformatted(text)
    end
end

local function text_fit(text)
    imgui.TextUnformatted(nimgui.truncate(text, imgui.GetContentRegionAvail().x))
end

local function draw_umum()
    local gap = theme.sp('sm')
    local avail = imgui.GetContentRegionAvail().x
    local tile_w = (avail - gap) / 2
    nimgui.stat_tile('Saldo', 'Rp 1.250.000', { width = tile_w })
    nimgui.same_line()
    nimgui.stat_tile('Status', cfg.enabled and 'Aktif' or 'Mati', { width = tile_w })
    nimgui.spacer()
    nimgui.checkbox('Aktifkan panel', cfg, 'enabled')
    nimgui.slider('Volume', cfg, 'volume', 0, 1)
    nimgui.input_text('Nama', cfg, 'name', 32)
end

local function draw_audio()
    nimgui.toggle('##suara', cfg, 'enabled')
    nimgui.same_line()
    imgui.TextUnformatted(cfg.enabled and 'Suara aktif' or 'Suara mati')
    nimgui.spacer()
    nimgui.segmented({ 'Stereo', 'Mono' }, cfg, 'channel')
    nimgui.input_float('Rasio', cfg, 'ratio', 0.05, 0.25)
    nimgui.spacer()
    nimgui.progress(cfg.ratio, {
        overlay = string.format('%d%%', math.floor(cfg.ratio * 100 + 0.5)),
    })
end

local function media_size()
    local width = imgui.GetContentRegionAvail().x
    return width, math.floor(width * 9 / 16 + 0.5)
end

local function draw_gif()
    local width, height = media_size()
    if anim == nil then
        nimgui.media.placeholder(width, height, { label = 'GIF tidak tersedia' })
        text_fit(anim_error or ('Letakkan ' .. GIF_FILE .. ' di folder script.'))
        return
    end

    nimgui.media.draw_anim(anim, width, height)

    if anim.loading then
        nimgui.progress(anim.progress or 0, {
            overlay = string.format('Memuat GIF %d%%',
                math.floor((anim.progress or 0) * 100 + 0.5)),
        })
        text_fit(string.format('%d frame | %dx%d',
            anim.frame_count, anim.width, anim.height))
    elseif anim.failed then
        text_fit('Gagal: ' .. tostring(anim.error))
    else
        text_fit(string.format('Animasi | %d frame | %dx%d',
            anim.frame_count, anim.width, anim.height))
        if anim.fallback then
            text_fit('Fallback: ' .. anim.fallback)
        end
    end
end

local function draw_image()
    local width, height = media_size()
    if image == nil then
        nimgui.media.placeholder(width, height, { label = 'Gambar tidak tersedia' })
        text_fit(image_error or ('Letakkan ' .. IMAGE_FILE .. ' di folder script.'))
        return
    end

    nimgui.media.image(image, width, height)
    text_fit(string.format('Gambar statis | %dx%d', IMAGE_W, IMAGE_H))
end

local function draw_media()
    local picked = nimgui.segmented({ 'GIF', 'Gambar' }, cfg, 'media')
    nimgui.spacer()
    if picked == 1 then
        draw_gif()
    else
        draw_image()
    end
end

local function draw_panel()
    local screen_w, screen_h = getScreenResolution()
    -- The first frame can report a zero or loading-screen size. Beginning the
    -- panel then would lock FirstUseEver to that tiny size and position.
    if type(screen_w) ~= 'number' or type(screen_h) ~= 'number'
        or screen_w < 320 or screen_h < 240 then
        return
    end

    local scale = theme and theme.scale or nimgui.scale()
    local panel_w = math.min(440, screen_w - 32)
    local panel_h = math.min(screen_h - 32, math.floor(250 + 340 * scale))

    local visible = nimgui.begin_panel('##nimgui_demo', {
        theme = theme,
        pos = { screen_w / 2, screen_h / 2 },
        pivot = { 0.5, 0.5 },
        size = { panel_w, panel_h },
        -- Keep the fixed size correct even if the first draw saw a bad screen size.
        size_cond = imgui.Cond.Always,
        flags = imgui.WindowFlags.NoTitleBar
            + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoSavedSettings,
    })

    if visible then
        draw_title('nimgui')
        text_fit('Contoh komponen untuk MonetLoader.')

        local tab = nimgui.segmented({ 'Umum', 'Audio', 'Media' }, cfg, 'tab')
        nimgui.separator()

        if tab == 1 then
            draw_umum()
        elseif tab == 2 then
            draw_audio()
        else
            draw_media()
        end

        nimgui.spacer()
        local gap = theme.sp('sm')
        local button_width = (imgui.GetContentRegionAvail().x - gap) / 2

        if nimgui.button('primary', 'Simpan', { width = button_width }) then
            nimgui.toast('Pengaturan disimpan')
        end
        nimgui.same_line()
        if nimgui.button('ghost', 'Tutup', { width = button_width }) then
            open = false
        end

        if font_error then
            nimgui.spacer()
            text_fit('Font: ' .. font_error)
        end
    end

    nimgui.end_panel()
end

imgui.OnInitialize(function()
    theme = nimgui.theme('instrument', { reduce_motion = false })

    local ok, err = nimgui.fonts.setup({
        base = { path = getWorkingDirectory() .. '/lib/mimgui/trebucbd.ttf', size = 14 },
        sizes = { body = 14, label = 11, display = 20 },
    })
    if not ok then
        font_error = err
    end

    local gif_path = getWorkingDirectory() .. '/' .. GIF_FILE
    if doesFileExist(gif_path) then
        local handle, load_err = nimgui.media.anim_async(gif_path)
        anim = handle
        anim_error = load_err
    else
        anim_error = 'Letakkan ' .. GIF_FILE .. ' di folder script.'
    end

    local image_path = getWorkingDirectory() .. '/' .. IMAGE_FILE
    if doesFileExist(image_path) then
        local handle, load_err = nimgui.media.load_file(image_path, {
            width = IMAGE_W,
            height = IMAGE_H,
        })
        image = handle
        image_error = load_err
    else
        image_error = 'Letakkan ' .. IMAGE_FILE .. ' di folder script.'
    end
end)

nimgui.render(
    function() return open end,
    function()
        if anim ~= nil and anim.loading then
            nimgui.media.step_anim(anim, 8)
        end
    end,
    function()
        draw_panel()
    end)

function main()
    sampRegisterChatCommand('nimgui', function()
        open = not open
    end)
    sampAddChatMessage('[nimgui] Ketik /nimgui untuk membuka contoh.', 0xFFFFFF)
    while true do
        wait(0)
    end
end
