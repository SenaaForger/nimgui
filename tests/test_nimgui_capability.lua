-- headless checks for nimgui capability probe
-- run: luajit tests/test_nimgui_capability.lua

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
local caps = nimgui.capabilities()

local version_ok = type(nimgui._VERSION) == 'string' and nimgui._VERSION:match('%d+%.%d+%.%d+') ~= nil
check('version is semver-like', version_ok, nimgui._VERSION)
check('capabilities is a table', type(caps) == 'table')
check('draw list detected', caps.draw_list == true)
check('add image detected', caps.add_image == true)
check('invisible button detected', caps.invisible_button == true)
check('cursor screen pos detected', caps.get_cursor_screen_pos == true)
check('same line detected', caps.same_line == true)
check('imvec2 detected', caps.imvec2 == true)
check('imvec4 detected', caps.imvec4 == true)
check('style detected', caps.style == true)
check('style colors detected', caps.style_colors == true)
check('cdata int/bool/float detected', caps.new_int and caps.new_bool and caps.new_float)
check('font atlas detected', caps.font_atlas == true)
check('font rebuild detected', caps.font_rebuild == true)
check('push font detected', caps.push_font == true)
check('texture file detected', caps.texture_file == true)
check('texture memory detected', caps.texture_memory == true)
check('release texture detected', caps.release_texture == true)
check('time detected', caps.time == true)
check('input text detected', caps.input_text == true)
check('slider float detected', caps.slider_float == true)
check('combo detected', caps.combo == true)
check('selectable detected', caps.selectable == true)
check('popup modal detected', caps.popup_modal == true)
check('tooltip detected', caps.tooltip == true)
check('dpi scale detected', caps.dpi_scale == true)
check('working directory detected', caps.working_directory == true)
check('file exists detected', caps.file_exists == true)
check('screen resolution detected', caps.screen_resolution == true)
check('event handler detected', caps.event_handler == true)
check('capabilities returns a copy', nimgui.capabilities() ~= caps)
check('theme factory exposed', type(nimgui.theme) == 'function')
check('state factory exposed', type(nimgui.state) == 'function')
check('scale exposed', type(nimgui.scale) == 'function')
check('render exposed', type(nimgui.render) == 'function')
check('shutdown exposed', type(nimgui.shutdown) == 'function')

check('render rejects non-function condition', not pcall(nimgui.render, 'not a function'))
check('render rejects missing draw', not pcall(nimgui.render, function() return true end))

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
