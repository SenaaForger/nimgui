-- headless checks for nimgui widgets
-- run: luajit tests/test_nimgui_widgets.lua

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

check('version stays 0.1.0', nimgui._VERSION == '0.1.0', nimgui._VERSION)
check('layout helpers are exported', type(nimgui.begin_panel) == 'function' and type(nimgui.truncate) == 'function')
check('widgets are exported', type(nimgui.button) == 'function' and type(nimgui.toast) == 'function')

fake.reset()
fake.buttonQueue = { true }
local pressed = nimgui.button('primary', 'Simpan')
check('primary button returns pressed', pressed == true)
local color_counts_ok = fake.colorPush == 4 and fake.colorPop == 4
check('button pushes and pops four colors', color_counts_ok, fake.colorPush .. '/' .. fake.colorPop)
check('button fills available width', fake.last.button.size.x == 320, fake.last.button.size.x)
check('button uses theme control height', fake.last.button.size.y == 44, fake.last.button.size.y)

fake.reset()
fake.buttonQueue = { true }
pressed = nimgui.button('secondary', 'Batal', { width = 120, height = 36 })
check('button accepts explicit size', fake.last.button.size.x == 120 and fake.last.button.size.y == 36)
check('secondary button reports press', pressed == true)

fake.reset()
fake.buttonQueue = { true }
pressed = nimgui.button('primary', 'Hapus', { disabled = true, disabled_hint = 'Tidak tersedia' })
check('disabled button ignores press', pressed == false)
check('disabled button balances alpha var', fake.varPush == 1 and fake.varPop == 1)
check('disabled button shows hint only on hover', fake.itemHovered == false and fake.count.BeginTooltip == 0)

fake.reset()
fake.itemHovered = true
fake.buttonQueue = { false }
nimgui.button('primary', 'Hapus', { disabled = true, disabled_hint = 'Tidak tersedia' })
check('hovered disabled button shows tooltip', fake.count.BeginTooltip == 1 and fake.count.EndTooltip == 1)

fake.reset()
fake.buttonQueue = { false, false }
nimgui.button('danger', 'Hapus')
nimgui.button('ghost', 'Lewati')
check('danger and ghost roles render', fake.count.Button == 2)

check('unknown button role raises', not pcall(nimgui.button, 'platinum', 'Simpan'))
check('button rejects empty label', not pcall(nimgui.button, 'primary', ''))

fake.reset()
local cfg = { tab = 1 }
fake.buttonQueue = { false, true, false }
local picked = nimgui.segmented({ 'Mobil', 'Motor', 'Kapal' }, cfg, 'tab', 0.016)
check('segmented returns clicked index', picked == 2, picked)
check('segmented writes state', cfg.tab == 2, cfg.tab)
check('segmented draws one button per item', fake.count.Button == 3, fake.count.Button)
check('segmented separates with SameLine', fake.count.SameLine == 2, fake.count.SameLine)
check('segmented uses control height', fake.last.button.size.y == 44)
check('segmented buttons share width', fake.last.button.size.x > 0)

fake.reset()
cfg = { tab = 99 }
local clamped = nimgui.segmented({ 'A', 'B' }, cfg, 'tab', 0.016)
check('segmented clamps invalid state', clamped == 1 and cfg.tab == 1, tostring(clamped) .. '/' .. tostring(cfg.tab))

fake.reset()
cfg = { sound = false }
fake.invisibleResult = true
local on = nimgui.toggle('##sound', cfg, 'sound', 0.016)
check('toggle flips state on click', on == true and cfg.sound == true)
check('toggle uses touch target', fake.last.invisible.size.x == 48 and fake.last.invisible.size.y == 44)
check('toggle draws track and knob', #fake.draw.rects == 1 and #fake.draw.circles == 1)

fake.reset()
cfg = { sound = true }
fake.drawListEnabled = false
fake.checkboxChanged = true
fake.checkboxValue = false
on = nimgui.toggle('##sound', cfg, 'sound', 0.016)
check('toggle fallback uses checkbox', fake.count.Checkbox == 1 and fake.count.InvisibleButton == 0)
check('toggle fallback writes state', on == false and cfg.sound == false, tostring(on))
fake.drawListEnabled = true

fake.reset()
cfg = { flag = false }
fake.checkboxChanged = true
fake.checkboxValue = true
local value = nimgui.checkbox('Aktif', cfg, 'flag')
check('checkbox returns new value', value == true and cfg.flag == true)
check('checkbox uses accent check mark', fake.colorPush == 4 and fake.colorPop == 4)

fake.reset()
cfg = { volume = 0 }
fake.sliderChanged = true
fake.sliderValue = 0.75
value = nimgui.slider('Volume', cfg, 'volume', 0, 1)
check('slider returns changed value', value == 0.75 and cfg.volume == 0.75, tostring(value))
check('slider stretches to content width', fake.last.itemWidth == -1, fake.last.itemWidth)
check('slider balances colors', fake.colorPush == 6 and fake.colorPop == 6, fake.colorPush .. '/' .. fake.colorPop)

fake.reset()
cfg = { count = 0 }
fake.inputIntChanged = true
fake.inputIntValue = 42
value = nimgui.input_int('Jumlah', cfg, 'count', 1, 10)
check('input_int returns changed value', value == 42 and cfg.count == 42, tostring(value))
check('input_int uses hidden label', fake.last.inputInt == '##count', fake.last.inputInt)

fake.reset()
cfg = { price = 0 }
fake.inputFloatChanged = true
fake.inputFloatValue = 1.25
value = nimgui.input_float('Harga', cfg, 'price', 0.1, 1)
check('input_float returns changed value', value == 1.25 and cfg.price == 1.25, tostring(value))

fake.reset()
cfg = { name = '' }
fake.inputTextChanged = true
fake.inputTextValue = 'hello'
value = nimgui.input_text('Nama', cfg, 'name', 32)
check('input_text returns changed text', value == 'hello' and cfg.name == 'hello', tostring(value))
fake.inputTextChanged = false
value = nimgui.input_text('Nama', cfg, 'name', 32)
check('input_text keeps value without change', value == 'hello', tostring(value))
check('input_text reuses one buffer', fake.count.InputText == 2 and fake.last.inputText == '##name')

fake.reset()
cfg = { flag = false }
local binder = nimgui.state(cfg)
fake.checkboxChanged = true
fake.checkboxValue = true
value = nimgui.checkbox('Aktif', binder, 'flag')
check('widgets accept a state binder', value == true and cfg.flag == true)

fake.reset()
cfg = { flag = false }
nimgui.checkbox('Aktif', cfg, 'flag')
nimgui.checkbox('Aktif', cfg, 'flag')
check('no cdata allocation after first frame', fake.newCalls == 1, fake.newCalls)

fake.reset()
nimgui.stat_tile('Uang', '1.250', { width = 100 })
check('stat tile opens and closes child', fake.count.BeginChild == 1 and fake.count.EndChild == 1)
check('stat tile draws label and value', fake.texts[1] == 'Uang' and fake.texts[2] == '1.250')
check('stat tile forwards width', fake.last.beginChild.size.x == 100)

fake.reset()
local shown = nimgui.progress(0.5)
check('progress draws fraction', fake.last.progress.fraction == 0.5 and shown == 0.5)
check('progress fills width by default', fake.last.progress.size.x == -1)
check('progress clamps above one', nimgui.progress(2) == 1)
check('progress clamps below zero', nimgui.progress(-1) == 0)
check('progress smooth starts at target', nimgui.progress(0.3, { smooth = true, dt = 0.016 }) == 0.3)

fake.reset()
fake.buttonQueue = { true }
local acted = nimgui.empty('Belum ada kendaraan', 'Tambahkan kendaraan pertama.', { action = 'Tambah' })
check('empty state draws title and hint',
    fake.texts[1] == 'Belum ada kendaraan' and fake.texts[2] == 'Tambahkan kendaraan pertama.')
check('empty state action reports press', acted == true)
check('empty state action is a button', fake.count.Button == 1)

fake.reset()
nimgui.tooltip('Menghapus tidak bisa dibatalkan')
check('tooltip opens and closes', fake.count.BeginTooltip == 1 and fake.count.EndTooltip == 1)
nimgui.tooltip(nil)
check('empty tooltip draws nothing', fake.count.BeginTooltip == 1)

fake.reset()
local drawn = 0
fake.modalResult = true
local is_open = nimgui.modal('confirm', 'Konfirmasi', function() drawn = drawn + 1 end, { open = true })
check('modal opens on rising edge', fake.count.OpenPopup == 1)
check('modal calls draw function', drawn == 1 and is_open == true)
check('modal ends popup', fake.count.EndPopup == 1)
nimgui.modal('confirm', 'Konfirmasi', function() drawn = drawn + 1 end, { open = true })
check('modal does not reopen while open', fake.count.OpenPopup == 1, fake.count.OpenPopup)

fake.reset()
fake.modalResult = true
fake.buttonQueue = { true }
nimgui.modal('confirm2', 'Tutup?', function() end, { open = true, close_label = 'Tutup' })
check('modal close label closes popup', fake.count.ClosePopup == 1)

check('modal rejects missing draw function', not pcall(nimgui.modal, 'x', 'X', nil))

check('toast alpha starts transparent', widgets.toast_alpha(0, false) == 0)
check('toast alpha eases in', math.abs(widgets.toast_alpha(0.09, false) - 0.875) < 0.001,
    widgets.toast_alpha(0.09, false))
check('toast alpha holds', widgets.toast_alpha(1.0, false) == 1)
check('toast alpha fades out', widgets.toast_alpha(2.57, false) < 1)
check('toast alpha respects reduce motion', widgets.toast_alpha(0, true) == 1)

fake.reset()
fake.time = 10
nimgui.toast('Tersimpan')
check('toast becomes active', widgets.toast_active() == true)
fake.time = 10.5
check('toast draws a window', widgets.draw_toast() == true and fake.count.Begin == 1)
check('toast writes its text', fake.texts[1] == 'Tersimpan')
check('toast ignores mouse input',
    fake.last.begin.flags % (2 * fake.WindowFlags.NoMouseInputs) >= fake.WindowFlags.NoMouseInputs)
fake.time = 13
check('toast expires', widgets.draw_toast() == false and widgets.toast_active() == false)

fake.reset()
fake.time = 10
nimgui.toast('Otomatis')
local frame_draw = 0
nimgui.render(function() return true end, function() frame_draw = frame_draw + 1 end)
fake.time = 10.5
fake.frame()
check('render draws the user callback', frame_draw == 1)
check('render draws the toast after the panel', fake.count.Begin == 1 and fake.texts[1] == 'Otomatis')
nimgui.shutdown()

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
