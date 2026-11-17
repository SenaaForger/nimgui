-- headless checks for nimgui media registry and animation playback
-- run: luajit tests/test_nimgui_media.lua

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

local nimgui = require 'nimgui'
local media = require 'nimgui.media'
local theme = require 'nimgui.theme'

local function read(path)
    local file = assert(io.open(path, 'rb'))
    local data = file:read('*a')
    file:close()
    return data
end

local anim = read(root .. '/tests/fixtures/anim.gif')
local interlaced = read(root .. '/tests/fixtures/interlaced.gif')
local static = read(root .. '/tests/fixtures/static.gif')

media.release_all()
fake.reset()

check('media is exported on the facade', nimgui.media == media)
check('media starts with empty stats', media.stats().textures == 0)

local handle, err = media.load_bytes('raw-image-bytes', 15, { width = 10, height = 20 })
check('raw bytes upload', handle ~= nil, err)
check('raw handle is static', handle and handle.animated == false)
check('raw handle keeps caller dimensions', handle and handle.width == 10 and handle.height == 20)
check('raw upload reaches the binding', fake.count.textureUploads == 1)
check('raw upload forwards byte size', fake.last.upload.size == 15, fake.last.upload.size)
check('raw stats count one texture', media.stats().textures == 1)
check('raw stats estimate pixels', media.stats().atlas_pixels == 200, media.stats().atlas_pixels)
check('raw stats estimate bytes', media.stats().estimated_bytes == 800)

media.image(handle, 40, 30)
check('image draws through imgui.Image', fake.count.Image == 1)
check('image forwards the requested size',
    fake.last.image.size.x == 40 and fake.last.image.size.y == 30)
check('image uses full texture UVs',
    fake.last.image.uv0.x == 0 and fake.last.image.uv0.y == 0
    and fake.last.image.uv1.x == 1 and fake.last.image.uv1.y == 1)
check('release reports success', media.release(handle) == true)
check('release frees the texture once', fake.count.textureReleases == 1)
check('release clears stats', media.stats().textures == 0 and media.stats().atlas_pixels == 0)

fake.reset()
local static_handle, static_err = media.load_file(root .. '/tests/fixtures/static.gif')
check('load_file reads a static GIF', static_handle ~= nil, static_err)
check('static GIF is not animated', static_handle and static_handle.animated == false)
check('static GIF keeps one frame', static_handle and static_handle.frame_count == 1)
check('static GIF decodes through the atlas path', fake.count.textureUploads == 1)
media.release(static_handle)

fake.reset()
local animated, anim_err = media.anim(root .. '/tests/fixtures/anim.gif')
check('anim reads an animated GIF', animated ~= nil, anim_err)
check('anim reports every frame', animated and animated.frame_count == 3, animated and animated.frame_count)
check('anim is marked animated', animated and animated.animated == true)
check('anim keeps loop count', animated and animated.loop_count == 0)
check('anim stats count every frame', media.stats().frames == 3)
check('anim uses a single texture', fake.count.textureUploads == 1)
local uploads_after_load = fake.count.textureUploads

fake.reset()
local frame = media.draw_anim(animated, 60, 60, 0.05)
check('animation starts on frame one', frame == 1, frame)
check('first frame uses the top cell',
    fake.draw.images[1].uv0.y == 0 and fake.draw.images[1].uv1.y == 1 / 3)
check('animation draws a quad at the requested size',
    fake.draw.images[1].b.x - fake.draw.images[1].a.x == 60
    and fake.draw.images[1].b.y - fake.draw.images[1].a.y == 60)
check('draw uses an opaque white tint', fake.draw.images[1].tint == 0xFFFFFFFF)
frame = media.draw_anim(animated, 60, 60, 0.06)
check('animation advances after the delay', frame == 2, frame)
check('second frame uses the middle cell',
    math.abs(fake.draw.images[2].uv0.y - 1 / 3) < 0.0001
    and math.abs(fake.draw.images[2].uv1.y - 2 / 3) < 0.0001)
check('draw callbacks never upload', fake.count.textureUploads == 0)
check('draw callbacks keep the load uploads', uploads_after_load == 1)

frame = media.draw_anim(animated, 60, 60, 0.11)
check('animation advances to the last frame', frame == 3, frame)
frame = media.draw_anim(animated, 60, 60, 0.21)
check('infinite animation wraps to frame one', frame == 1, frame)
media.release(animated)

fake.reset()
local finite, finite_err = media.anim_bytes(interlaced, #interlaced)
check('finite loop GIF loads', finite ~= nil, finite_err)
check('finite loop keeps its count', finite and finite.loop_count == 1)
frame = media.draw_anim(finite, 40, 40, 1.0)
check('finite animation stops on the last frame', finite.stopped and frame == 2, frame)
media.draw_anim(finite, 40, 40, 1.0)
check('stopped animation stays on the last frame', finite.frame_index == 2)
media.release(finite)

fake.reset()
theme.push(theme.make('graphite', { reduce_motion = true }))
local calm, calm_err = media.anim_bytes(anim, #anim)
check('reduce motion animation loads', calm ~= nil, calm_err)
frame = media.draw_anim(calm, 30, 30, 5.0)
check('reduce motion pins frame one', frame == 1 and calm.frame_index == 1)
theme.pop_all()
media.release(calm)

fake.reset()
local scaled_handle, scaled_err = media.anim_bytes(anim, #anim, { max_atlas_pixels = 100 })
check('animation downscales to fit its budget', scaled_handle ~= nil, scaled_err)
check('downscaled animation stays animated', scaled_handle and scaled_handle.animated == true)
check('downscaled handle reports its scale', scaled_handle and scaled_handle.scale < 1,
    scaled_handle and scaled_handle.scale)
check('downscaled stats stay inside the budget',
    scaled_handle and media.stats().atlas_pixels <= 100, media.stats().atlas_pixels)
media.release(scaled_handle)

fake.reset()
local pending, pending_err = media.anim_bytes_async(anim, #anim)
check('async animation returns a loading handle', pending ~= nil, pending_err)
check('async handle starts loading', pending and pending.loading == true)
check('async handle knows its frame count', pending and pending.frame_count == 3,
    pending and pending.frame_count)
check('async handle has no texture yet', pending and pending.tex == nil)
check('async handle does not upload at load time', fake.count.textureUploads == 0)
check('async handle does not count stats yet', media.stats().textures == 0)
local stepped, step_err = media.step_anim(pending, 10)
check('async step returns a status', stepped == true or stepped == nil, step_err)
for _ = 1, 20 do
    if not pending.loading then
        break
    end
    media.step_anim(pending, 10)
end
check('async animation finishes loading', pending.loading == false)
check('async animation becomes animated', pending.animated == true)
check('async animation uploads one texture', fake.count.textureUploads == 1)
check('async animation progress reaches one', pending.progress == 1, pending.progress)
check('async animation draws its first frame', media.draw_anim(pending, 40, 40, 0.05) == 1)
media.release(pending)

fake.reset()
local pending_file, pending_file_err = media.anim_async(root .. '/tests/fixtures/anim.gif')
check('anim_async reads a file', pending_file ~= nil, pending_file_err)
check('anim_async returns a loading handle', pending_file and pending_file.loading == true)
media.release(pending_file)

fake.reset()
local abandoned, abandoned_err = media.anim_bytes_async(anim, #anim)
check('loading handle can be released', media.release(abandoned) == true, abandoned_err)
check('releasing a loading handle leaves stats empty', media.stats().textures == 0)
check('released loading handle refuses to step', media.step_anim(abandoned) == false)
check('released loading handle draws a placeholder', media.draw_anim(abandoned, 40, 40) == nil)

fake.reset()
local fallback, fallback_err = media.anim_bytes(anim, #anim, {
    max_atlas_pixels = 100,
    allow_scale = false,
})
check('over-budget animation falls back', fallback ~= nil, fallback_err)
check('fallback is static', fallback and fallback.animated == false)
check('fallback keeps one frame', fallback and fallback.frame_count == 1)
check('fallback records the reason', fallback and type(fallback.fallback) == 'string')
check('fallback stats count one frame', media.stats().frames == 1)
media.release(fallback)

fake.reset()
fake.uploadFail = true
local failed, fail_err = media.load_bytes(static, #static)
check('upload failure returns an error', failed == nil and type(fail_err) == 'string', fail_err)
failed, fail_err = media.anim_bytes(anim, #anim)
check('animation upload failure reports fallback', failed == nil and type(fail_err) == 'string')
fake.uploadFail = false

fake.reset()
local twice = media.anim_bytes(interlaced, #interlaced)
local releases_before = fake.count.textureReleases
check('release is idempotent', media.release(twice) == true and media.release(twice) == true)
check('idempotent release frees once', fake.count.textureReleases == releases_before + 1,
    fake.count.textureReleases)
check('releasing an invalid handle reports an error', media.release('nope') == false)

fake.reset()
local first = media.anim_bytes(anim, #anim)
local second = media.load_bytes(static, #static)
check('two handles are registered', media.stats().textures == 2)
check('shutdown releases every texture', nimgui.shutdown() == true)
check('shutdown clears the registry', media.stats().textures == 0 and media.stats().frames == 0)
check('shutdown releases both textures', fake.count.textureReleases == 2,
    fake.count.textureReleases)
check('shutdown is idempotent', nimgui.shutdown() == true)
check('second shutdown does not free again', fake.count.textureReleases == 2)
media.release(first)
media.release(second)

fake.reset()
media.placeholder(120, 60, { label = 'Kosong' })
check('placeholder reserves layout space', fake.count.Dummy == 1 and fake.last.dummy.y == 60)
check('placeholder draws fill and border', #fake.draw.rects == 2, #fake.draw.rects)
check('placeholder writes its label', fake.draw.texts[1].text == 'Kosong')
check('placeholder rejects invalid size', not pcall(media.placeholder, 0, 10))

local missing = media.load_file(root .. '/tests/fixtures/missing.gif')
check('missing file reports an error', missing == nil)
check('short slice reports an error', media.load_bytes(static, 3) == nil)
check('non-GIF animation reports an error', media.anim_bytes('plain', 5) == nil)

local stats_copy = media.stats()
stats_copy.textures = 99
check('stats returns a copy', media.stats().textures == 0, media.stats().textures)

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
