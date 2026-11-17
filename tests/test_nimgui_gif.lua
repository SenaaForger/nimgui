-- headless checks for the nimgui GIF decoder and atlas encoders
-- run: luajit tests/test_nimgui_gif.lua

local root = arg[0]:gsub('\\', '/'):match('^(.*)/tests/[^/]+$') or '.'

MONET_DPI_SCALE = 1.0
function getWorkingDirectory() return '.' end
function doesFileExist() return true end
function getScreenResolution() return 1280, 720 end
function addEventHandler() end

local fake = dofile(root .. '/tests/fake_nimgui.lua')
package.path = root .. '/dist/lib/?.lua;' .. root .. '/dist/lib/?/init.lua;' .. package.path
package.preload['mimgui'] = function() return fake end

local failures, checks = 0, 0

local function check(name, condition, detail)
    checks = checks + 1
    if condition then
        print('ok   - ' .. name)
    else
        failures = failures + 1
        print('FAIL - ' .. name .. (detail and (' :: ' .. tostring(detail)) or ''))
    end
end

local gif = require 'nimgui.gif'

local function read(path)
    local file = assert(io.open(path, 'rb'))
    local data = file:read('*a')
    file:close()
    return data
end

local anim = read(root .. '/tests/fixtures/anim.gif')
local interlaced = read(root .. '/tests/fixtures/interlaced.gif')
local pattern = read(root .. '/tests/fixtures/pattern.gif')
local static = read(root .. '/tests/fixtures/static.gif')

local function pixel(atlas, frame, x, y)
    local col = (frame - 1) % atlas.cols
    local row = math.floor((frame - 1) / atlas.cols)
    local cell_w = atlas.cell_width or atlas.width
    local cell_h = atlas.cell_height or atlas.height
    local offset = ((row * cell_h + y) * atlas.atlas_width + col * cell_w + x) * 4
    local data = atlas.data
    return data[offset], data[offset + 1], data[offset + 2], data[offset + 3]
end

local info = gif.info(anim)
check('info reports logical screen', info.width == 6 and info.height == 6)
check('info reports frame count', info.frame_count == 3, info.frame_count)
check('info reports loop count', info.loop_count == 0, info.loop_count)
check('info converts delays to ms', info.delays[1] == 100 and info.delays[2] == 50
    and info.delays[3] == 200)

local atlas = gif.decode(anim)
check('animated GIF decodes', atlas ~= nil)
check('atlas holds every frame', atlas.frame_count == 3, atlas.frame_count)
check('atlas is one column for a tall grid', atlas.cols == 1 and atlas.rows == 3,
    atlas.cols .. 'x' .. atlas.rows)
check('atlas size matches pixel budget', atlas.atlas_width == 6 and atlas.atlas_height == 18)
check('atlas byte size is width*height*4', atlas.size == 6 * 18 * 4, atlas.size)

local r, g, b, a = pixel(atlas, 1, 0, 0)
check('first frame is opaque red', r == 255 and g == 0 and b == 0 and a == 255)
r, g, b, a = pixel(atlas, 2, 0, 0)
check('transparent frame keeps alpha zero', a == 0, a)
r, g, b, a = pixel(atlas, 2, 0, 3)
check('second frame paints blue below the line', r == 0 and g == 0 and b == 255 and a == 255)
r, g, b, a = pixel(atlas, 3, 0, 3)
check('disposal restores the old background', a == 0, a)
r, g, b, a = pixel(atlas, 3, 4, 4)
check('frame rectangle offset is applied', r == 255 and g == 255 and b == 255 and a == 255)

local first = gif.first_frame(anim)
check('first_frame returns one frame', first.frame_count == 1, first.frame_count)
check('first_frame uses a single cell', first.atlas_width == 6 and first.atlas_height == 6)

local inter = gif.decode(interlaced)
check('interlaced GIF decodes', inter ~= nil)
local colors = { { 255, 0, 0 }, { 0, 255, 0 }, { 0, 0, 255 }, { 255, 255, 0 } }
local expected_rows = { 1, 1, 1, 1, 2, 2, 2, 2 }
local inter_ok = true
for y = 0, 7 do
    local er, eg, eb = colors[expected_rows[y + 1]][1], colors[expected_rows[y + 1]][2],
        colors[expected_rows[y + 1]][3]
    local pr, pg, pb, pa = pixel(inter, 1, 0, y)
    if pr ~= er or pg ~= eg or pb ~= eb or pa ~= 255 then
        inter_ok = false
        break
    end
end
check('interlace pass order is rebuilt', inter_ok)

local inter2_ok = true
for y = 0, 7 do
    local expected = y < 2 and colors[3] or colors[1]
    local pr, pg, pb = pixel(inter, 2, 0, y)
    if pr ~= expected[1] or pg ~= expected[2] or pb ~= expected[3] then
        inter2_ok = false
        break
    end
end
check('second interlaced frame composites', inter2_ok)

local pattern_atlas = gif.decode(pattern)
check('small LZW code size decodes', pattern_atlas ~= nil)
local pattern_ok = true
for y = 0, 31 do
    for x = 0, 31 do
        local expected = colors[(math.floor(x / 2) + math.floor(y / 2)) % 4 + 1]
        local pr, pg, pb, pa = pixel(pattern_atlas, 1, x, y)
        if pr ~= expected[1] or pg ~= expected[2] or pb ~= expected[3] or pa ~= 255 then
            pattern_ok = false
            break
        end
    end
    if not pattern_ok then
        break
    end
end
check('dictionary growth keeps pixels aligned', pattern_ok)

local decoder = gif.decoder(anim)
check('decoder exposes progressive steps', decoder ~= nil)
local status, step_err = decoder:step(1)
check('one row returns more work', status == 'more', status .. '/' .. tostring(step_err))
local frame_events, done = 0, false
for _ = 1, 100 do
    status, step_err = decoder:step(2)
    if status == nil then
        break
    end
    if status == 'frame' then
        frame_events = frame_events + 1
    elseif status == 'done' then
        done = true
        break
    end
end
check('progressive decode finishes', done)
check('progressive decode emits each frame', frame_events == 3, frame_events)

local rejected, budget_err = gif.decode(anim, { max_atlas_pixels = 100, allow_scale = false })
check('strict atlas budget rejects the animation',
    rejected == nil and type(budget_err) == 'string', budget_err)
local fitted, fit_err = gif.decode(anim, { max_atlas_pixels = 100 })
check('atlas budget downscales the animation', fitted ~= nil, fit_err)
check('downscaled atlas stays inside the budget', fitted and fitted.atlas_pixels <= 100,
    fitted and fitted.atlas_pixels)
check('downscaled atlas reports its scale', fitted and fitted.scale < 1, fitted and fitted.scale)
local fr, fg, fb, fa = pixel(fitted, 1, 0, 0)
check('downscaled first frame keeps its color', fr == 255 and fg == 0 and fb == 0 and fa == 255,
    string.format('%s,%s,%s,%s', tostring(fr), tostring(fg), tostring(fb), tostring(fa)))

local scaled = gif.decode(pattern, { max_atlas_pixels = 400 })
check('square atlas downscales', scaled ~= nil and scaled.scale < 1,
    scaled and scaled.scale)
local scale_ok = true
for y = 0, scaled.cell_height - 1 do
    for x = 0, scaled.cell_width - 1 do
        local source_x = math.floor(x * 32 / scaled.cell_width)
        local source_y = math.floor(y * 32 / scaled.cell_height)
        local expected = colors[(math.floor(source_x / 2) + math.floor(source_y / 2)) % 4 + 1]
        local pr, pg, pb, pa = pixel(scaled, 1, x, y)
        if pr ~= expected[1] or pg ~= expected[2] or pb ~= expected[3] or pa ~= 255 then
            scale_ok = false
            break
        end
    end
    if not scale_ok then
        break
    end
end
check('downscaled atlas keeps sampled pixels', scale_ok)

rejected, budget_err = gif.decode(anim, { max_frames = 2 })
check('frame budget rejects the animation', rejected == nil and type(budget_err) == 'string')
rejected, budget_err = gif.decode(anim, { max_dimension = 4 })
check('dimension budget rejects the animation', rejected == nil and type(budget_err) == 'string')
rejected, budget_err = gif.decode('GIF89a')
check('truncated input reports an error', rejected == nil and type(budget_err) == 'string')
rejected, budget_err = gif.decode('not a gif at all')
check('non-GIF input reports an error', rejected == nil and type(budget_err) == 'string')

local static_atlas = gif.decode(static)
check('static GIF decodes one frame', static_atlas.frame_count == 1)
local bmp, bmp_size = gif.encode_bmp(static_atlas)
check('BMP starts with the signature', bmp[0] == 66 and bmp[1] == 77)
check('BMP declares its full size', bmp_size == 54 + 6 * 6 * 4, bmp_size)
check('BMP uses a 54 byte pixel offset', bmp[10] == 54, bmp[10])
check('BMP stores 32 bits per pixel', bmp[28] == 32, bmp[28])
check('BMP has no compression', bmp[30] == 0, bmp[30])
check('BMP pixels are BGRA red', bmp[54] == 0 and bmp[55] == 0 and bmp[56] == 255
    and bmp[57] == 255)
check('BMP writes rows bottom-up', bmp[58] == 0 and bmp[59] == 0 and bmp[60] == 255)

local anim_bmp = gif.encode_bmp(atlas)
local transparent_offset = 54 + (atlas.atlas_height - 1 - 6) * atlas.atlas_width * 4
check('BMP keeps transparency alpha', anim_bmp[transparent_offset + 3] == 0)

local tga, tga_size = gif.encode_tga(static_atlas)
check('TGA declares true-color type', tga[2] == 2, tga[2])
check('TGA stores 32 bits per pixel', tga[16] == 32, tga[16])
check('TGA uses top-left origin and alpha', tga[17] == 0x28, tga[17])
check('TGA size includes its header', tga_size == 18 + 6 * 6 * 4, tga_size)
check('TGA pixels are BGRA red', tga[18] == 0 and tga[19] == 0 and tga[20] == 255
    and tga[21] == 255)

check('TGA fallback encoder rejects missing data', not pcall(gif.encode_tga, {}))

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
