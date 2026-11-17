-- headless checks for nimgui layout helpers
-- run: luajit tests/test_nimgui_layout.lua

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
local layout = require 'nimgui.layout'
local theme = require 'nimgui.theme'

check('grid fits four cells', nimgui.grid_columns(328, 64, 8) == 4, nimgui.grid_columns(328, 64, 8))
check('grid never drops below one column', nimgui.grid_columns(40, 64, 8) == 1, nimgui.grid_columns(40, 64, 8))
check('grid accepts exact width', nimgui.grid_columns(64, 64, 8) == 1, nimgui.grid_columns(64, 64, 8))
check('grid rejects zero cell width', not pcall(nimgui.grid_columns, 320, 0, 8))

check('short text is not truncated', nimgui.truncate('abc', 100) == 'abc')
check('long text gains ellipsis', nimgui.truncate('abcdefghij', 35) == 'ab...', nimgui.truncate('abcdefghij', 35))
check('truncate keeps utf8 boundaries', nimgui.truncate(string.rep('\195\169', 5), 35) == '\195\169...',
    nimgui.truncate(string.rep('\195\169', 5), 35))
check('truncate handles tiny budgets', nimgui.truncate('abcdef', 5) == '...', nimgui.truncate('abcdef', 5))

check('footer height follows theme', nimgui.footer_height() == 56, nimgui.footer_height())

fake.reset()
theme.pop_all()
layout.reset()

local visible = nimgui.begin_panel('##panel')
check('begin_panel returns Begin result', visible == true)
check('begin_panel calls Begin once', fake.count.Begin == 1, fake.count.Begin)
check('begin_panel installs fallback theme', theme.current() ~= nil)
check('end_panel returns true', nimgui.end_panel() == true)
check('end_panel calls End once', fake.count.End == 1, fake.count.End)
check('end_panel restores theme stack', theme.current() == nil)
check('panel colors balanced', fake.colorPush == fake.colorPop, fake.colorPush .. '/' .. fake.colorPop)
check('panel vars balanced', fake.varPush == fake.varPop, fake.varPush .. '/' .. fake.varPop)

local t = theme.make('instrument', { scale = 1.0 })
fake.reset()
visible = nimgui.begin_panel('##explicit', { theme = t, open = nil })
check('explicit theme panel opens', visible == true)
check('explicit theme is active inside panel', theme.current() == t)
check('explicit theme pushes colors', fake.colorPush == t.push_colors, fake.colorPush)
nimgui.end_panel()
check('explicit theme pops colors', fake.colorPop == t.push_colors, fake.colorPop)
check('explicit theme cleared after end', theme.current() == nil)

fake.reset()
nimgui.begin_panel('##alpha', { theme = t, alpha = 0.5 })
check('panel alpha pushes a style var', fake.varPush == t.push_vars + 1, fake.varPush)
nimgui.end_panel()
check('panel alpha pops a style var', fake.varPop == fake.varPush, fake.varPop .. '/' .. fake.varPush)

fake.reset()
nimgui.begin_panel('##placed', {
    theme = t,
    pos = { 10, 20 },
    pivot = { 1, 0 },
    anchored = true,
    size = { 200, 100 },
    min = { 120, 60 },
    max = { 400, 300 },
})
local pos = fake.last.windowPos
check('panel position is applied', fake.count.SetNextWindowPos == 1 and pos.pos.x == 10 and pos.pos.y == 20)
check('anchored panel uses Always', pos.cond == fake.Cond.Always, pos.cond)
check('panel pivot is applied', pos.pivot.x == 1 and pos.pivot.y == 0)
check('panel size is applied', fake.count.SetNextWindowSize == 1 and fake.last.windowSize.size.x == 200)
check('panel constraints are applied', fake.count.SetNextWindowSizeConstraints == 1)
check('constraints keep min and max', fake.last.constraints.min.y == 60 and fake.last.constraints.max.x == 400)
nimgui.end_panel()

fake.reset()
nimgui.begin_panel('##fixed_size', {
    theme = t,
    pos = { 10, 20 },
    size = { 200, 100 },
    size_cond = fake.Cond.Always,
})
check('size_cond overrides the default size condition',
    fake.last.windowSize.cond == fake.Cond.Always, fake.last.windowSize.cond)
check('size_cond keeps the position on FirstUseEver',
    fake.last.windowPos.cond == fake.Cond.FirstUseEver, fake.last.windowPos.cond)
nimgui.end_panel()

fake.reset()
local child_visible = nimgui.begin_child('body', { 120, 80 }, true)
check('begin_child returns BeginChild result', child_visible == true)
check('begin_child forwards size and border',
    fake.last.beginChild.size.x == 120 and fake.last.beginChild.border == true)
check('end_child returns true', nimgui.end_child() == true)
check('end_child calls EndChild once', fake.count.EndChild == 1, fake.count.EndChild)
check('extra end_child reports error', nimgui.end_child() == false)

fake.reset()
nimgui.spacer(12)
check('spacer draws a dummy', fake.count.Dummy == 1 and fake.last.dummy.y == 12, fake.last.dummy and fake.last.dummy.y)
nimgui.same_line()
check('same_line forwards to imgui', fake.count.SameLine == 1)
nimgui.separator()
check('separator forwards to imgui', fake.count.Separator == 1)

fake.reset()
nimgui.begin_panel('##dangling', { theme = t })
nimgui.begin_child('inside', { 50, 50 }, false)
check('open stacks before reset', layout.depth() == 1)
layout.reset()
local panels, children = layout.depth()
check('reset closes children and panels', panels == 0 and children == 0, panels .. '/' .. children)
check('reset calls EndChild then End', fake.count.EndChild == 1 and fake.count.End == 1)
check('reset restores theme stack', theme.current() == nil)

check('begin_panel rejects empty id', not pcall(nimgui.begin_panel, ''))
check('begin_child rejects empty id', not pcall(nimgui.begin_child, ''))
check('end_panel without begin reports error', nimgui.end_panel() == false)
check('spacer rejects non-number', not pcall(nimgui.spacer, 'big'))

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
