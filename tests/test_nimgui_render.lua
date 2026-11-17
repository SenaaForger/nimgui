-- headless checks for nimgui render lifecycle and shutdown
-- run: luajit tests/test_nimgui_render.lua

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
local theme = require 'nimgui.theme'

fake.reset()

local noop = function() end
local cond_true = function() return true end

local drawn = 0
local sub = nimgui.render(cond_true, noop, function() drawn = drawn + 1 end)
check('render returns subscription', type(sub) == 'table' and type(sub.Unsubscribe) == 'function', type(sub))
check('subscription is tracked', fake.subs[#fake.subs] == sub)

fake.frame()
check('draw callback ran once', drawn == 1, drawn)

local before_calls = 0
local draw_two = 0
local sub_two = nimgui.render(cond_true,
    function() before_calls = before_calls + 1 end,
    function() draw_two = draw_two + 1 end)
fake.frame()
check('second subscription ran', draw_two == 1, draw_two)
check('before callback ran', before_calls == 1, before_calls)

local ok = nimgui.shutdown()
check('shutdown returns true', ok == true)
check('subscription unsubscribed', sub.unsubscribed == true and sub_two.unsubscribed == true)
check('second shutdown is idempotent', nimgui.shutdown() == true)

local calls = 0
nimgui.add_shutdown_handler(function() calls = calls + 1 end)
nimgui.shutdown()
nimgui.shutdown()
check('shutdown handlers run once', calls == 1, calls)

check('render rejects non-function draw', not pcall(nimgui.render, cond_true, noop, 'nope'))
check('render rejects non-function before', not pcall(nimgui.render, cond_true, 'nope', noop))

local t = theme.make('instrument', { scale = 1.0 })
theme.push(t)
nimgui.render(cond_true, noop, function() error('boom', 0) end)
local frame_ok, frame_err = pcall(fake.frame)
check('draw error propagates', not frame_ok, frame_err)
check('theme stack restored after draw error', theme.depth() == 0, theme.depth())

local drawn_two_arg = 0
fake.reset()
local sub_two_arg = nimgui.render(cond_true, function() drawn_two_arg = drawn_two_arg + 1 end)
fake.frame()
check('two-argument render works as draw-only', drawn_two_arg == 1, drawn_two_arg)
check('two-argument subscription returned', type(sub_two_arg) == 'table')

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
