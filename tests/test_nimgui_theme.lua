-- headless checks for nimgui theme tokens and style stack
-- run: luajit tests/test_nimgui_theme.lua

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

local theme = require 'nimgui.theme'
local color = require 'color'

fake.reset()
local t = theme.make('instrument', { scale = 1.0 })

check('theme scale applied', t.scale == 1.0, t.scale)
check('spacing lg follows scale', t.sp('lg') == 16, t.sp('lg'))
check('control height follows scale', t.control_h == 44, t.control_h)
check('radius follows scale', t.radius == 4, t.radius)
check('raw palette is present', type(t.raw.bg) == 'number' and type(t.raw.accent) == 'number')
check('packed colors are present', type(t.color.accent) == 'number' and type(t.color.bg) == 'number')
local text_contrast = color.contrast(t.raw.text, t.raw.bg)
local accent_contrast = color.contrast(t.raw.accent, t.raw.bg)
check('text/bg contrast at least 4.5', text_contrast >= 4.5, text_contrast)
check('accent/bg contrast at least 3', accent_contrast >= 3, accent_contrast)
check('push counts recorded', t.push_colors == 23 and t.push_vars == 9, t.push_colors .. '/' .. t.push_vars)
check('reduce motion is false by default', t.reduce_motion == false)

local light = theme.make('paper', { scale = 1.0 })
check('paper direction is light mode', light.mode == 'light', light.mode)

local custom_spec = { hue = 215, tint = 0.14, accentHue = 40, accentSat = 0.75, accentLight = 0.62 }
local custom = theme.make(custom_spec, { scale = 2.0 })
check('custom spec follows scale', custom.scale == 2.0 and custom.sp('sm') == 16, custom.sp('sm'))

check('unknown direction raises', not pcall(theme.make, 'nope'))
check('unknown spacing token raises', not pcall(function() return t.sp('nope') end))
check('push rejects non-table', not pcall(theme.push, 'nope'))

fake.reset()
theme.push(t)
check('push pushes all theme colors', fake.colorPush == 23, fake.colorPush)
check('push pushes all theme vars', fake.varPush == 9, fake.varPush)
check('depth is 1 after push', theme.depth() == 1, theme.depth())
check('current theme is set', theme.current() == t)

theme.push(t)
check('depth is 2 after second push', theme.depth() == 2, theme.depth())

theme.pop()
check('pop pops one theme', fake.colorPop == 23 and fake.varPop == 9, fake.colorPop .. '/' .. fake.varPop)
check('depth is 1 after pop', theme.depth() == 1, theme.depth())

theme.pop_all()
check('pop_all clears depth', theme.depth() == 0, theme.depth())
check('pop_all balances colors', fake.colorPop == 46, fake.colorPop)
check('pop_all balances vars', fake.varPop == 18, fake.varPop)
check('current theme cleared', theme.current() == nil)

local popped, err = theme.pop()
check('pop without push reports error', popped == false and type(err) == 'string', tostring(err))

MONET_DPI_SCALE = 1.5
check('scale reads MONET_DPI_SCALE', theme.scale() == 1.5, theme.scale())

local active = theme.active()
check('active returns a fallback theme', type(active) == 'table' and type(active.color) == 'table')
check('active fallback follows scale', active.scale == 1.5, active.scale)
check('active fallback is cached', theme.active() == active)

local applied = theme.apply('dispatch')
check('apply returns a theme', applied ~= nil and type(applied.color) == 'table')
check('apply sets current theme', theme.current() == applied)

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
