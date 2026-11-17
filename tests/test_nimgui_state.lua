-- headless checks for nimgui state binding
-- run: luajit tests/test_nimgui_state.lua

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
fake.reset()

check('state rejects non-table', not pcall(nimgui.state, 'nope'))

local cfg = { source = 7, block_kick = true, progress = 0.5 }
local binder = nimgui.state(cfg)
local has_binders = type(binder.int) == 'function'
    and type(binder.bool) == 'function'
    and type(binder.float) == 'function'
check('binder exposes int/bool/float', has_binders)

local source = binder:int('source', -1)
check('int proxy reads state', source:get() == 7, source:get())
check('int cdata initialised from state', source:value() == 7, source:value())
check('int cdata created once', fake.newCalls == 1, fake.newCalls)
check('int proxy is cached', binder:int('source') == source)
check('cached proxy does not allocate again', fake.newCalls == 1, fake.newCalls)

source:set(9)
check('proxy set writes state', cfg.source == 9, cfg.source)
source:refresh()
check('refresh copies state to cdata', source:value() == 9, source:value())

source:cdata()[0] = 12
source:commit()
check('commit copies cdata to state', cfg.source == 12, cfg.source)

local missing = binder:int('missing', 5)
check('default used when state key missing', missing:value() == 5, missing:value())
check('missing state key reads nil', missing:get() == nil, missing:get())

local flag = binder:bool('block_kick', false)
check('bool proxy reads state', flag:get() == true)
flag:cdata()[0] = false
flag:commit()
check('bool commit writes state', cfg.block_kick == false, cfg.block_kick)

local progress = binder:float('progress', 0)
check('float proxy reads state', progress:get() == 0.5, progress:get())

check('four cdata objects created', fake.newCalls == 4, fake.newCalls)
check('key must be a string', not pcall(binder.int, binder, 123))
check('state setter writes through', (function() binder:set('other', 1) return cfg.other == 1 end)())

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
