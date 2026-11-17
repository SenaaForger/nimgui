-- headless checks for P3 polish: touch targets, reduced motion, toast focus
-- run: luajit tests/test_nimgui_polish.lua

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
local widgets = require 'nimgui.widgets'
local theme = require 'nimgui.theme'

local function last_frame_padding()
    for index = #fake.styleVarPushes, 1, -1 do
        local push = fake.styleVarPushes[index]
        if push.name == fake.StyleVar.FramePadding then
            return push.value
        end
    end
end

local function frame_height(draw)
    fake.reset()
    draw()
    local padding = last_frame_padding()
    if padding == nil then
        return nil
    end
    return fake.fontSize + 2 * padding.y
end

local cfg = { flag = false, volume = 0, count = 0, ratio = 0, name = '' }
local height = frame_height(function() nimgui.checkbox('Aktif', cfg, 'flag') end)
check('checkbox reaches the touch target', height == 44, height)
height = frame_height(function() nimgui.slider('Volume', cfg, 'volume', 0, 1) end)
check('slider reaches the touch target', height == 44, height)
height = frame_height(function() nimgui.input_int('Jumlah', cfg, 'count') end)
check('input_int reaches the touch target', height == 44, height)
height = frame_height(function() nimgui.input_float('Rasio', cfg, 'ratio') end)
check('input_float reaches the touch target', height == 44, height)
height = frame_height(function() nimgui.input_text('Nama', cfg, 'name') end)
check('input_text reaches the touch target', height == 44, height)

fake.reset()
fake.fontSize = 21
local scaled = theme.make('graphite', { scale = 1.5 })
theme.push(scaled)
nimgui.slider('Volume', cfg, 'volume', 0, 1)
theme.pop_all()
local padding = last_frame_padding()
height = fake.fontSize + 2 * padding.y
check('scaled control height follows 44*S', height == 66, height)

fake.reset()
theme.push(theme.make('graphite', { scale = 1, reduce_motion = true }))
local active = theme.active()
cfg = { sound = false }
widgets.toggle('##sound', cfg, 'sound', 0.016)
cfg.sound = true
widgets.toggle('##sound', cfg, 'sound', 0.016)
check('reduced motion jumps the toggle to its target',
    fake.draw.rects[2].col == active.color.accent, fake.draw.rects[2].col)
theme.pop_all()

fake.reset()
theme.push(theme.make('graphite', { scale = 1, reduce_motion = false }))
cfg = { sound = false }
widgets.toggle('##sound', cfg, 'sound', 0.016)
cfg.sound = true
widgets.toggle('##sound', cfg, 'sound', 0.001)
check('normal motion keeps the toggle in between',
    fake.draw.rects[2].col ~= active.color.accent, fake.draw.rects[2].col)
theme.pop_all()
widgets.reset()

theme.push(theme.make('graphite', { scale = 1, reduce_motion = false }))
nimgui.progress(0.8, { smooth = true, id = 'job', dt = 0.016 })
theme.pop_all()
theme.push(theme.make('graphite', { scale = 1, reduce_motion = true }))
local shown = nimgui.progress(0.2, { smooth = true, id = 'job', dt = 0.016 })
check('reduced motion snaps smoothed progress', shown == 0.2, shown)
theme.pop_all()
widgets.reset()

theme.push(theme.make('graphite', { scale = 1, reduce_motion = false }))
nimgui.progress(0.8, { smooth = true, id = 'job', dt = 0.016 })
local moving = nimgui.progress(0.2, { smooth = true, id = 'job', dt = 0.016 })
check('normal motion smooths progress', moving > 0.2 and moving < 0.8, moving)
theme.pop_all()
widgets.reset()

fake.reset()
nimgui.toast('Tersimpan')
widgets.draw_toast()
local flags = fake.last.begin.flags
local no_mouse = flags % (fake.WindowFlags.NoMouseInputs * 2) >= fake.WindowFlags.NoMouseInputs
local no_nav = flags % (fake.WindowFlags.NoNavInputs * 2) >= fake.WindowFlags.NoNavInputs
check('toast ignores mouse input', no_mouse, flags)
check('toast ignores keyboard navigation', no_nav, flags)

check('footer height reserves control plus spacing', nimgui.footer_height() == 44 + 12,
    nimgui.footer_height())

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
