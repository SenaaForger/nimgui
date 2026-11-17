-- headless checks for the nimgui font manager
-- run: luajit tests/test_nimgui_fonts.lua

local root = arg[0]:gsub('\\', '/'):match('^(.*)/tests/[^/]+$') or '.'

MONET_DPI_SCALE = 1.0
function getWorkingDirectory() return '.' end
function getScreenResolution() return 1280, 720 end
function addEventHandler() end

local missing = {}
missing['missing.ttf'] = true
function doesFileExist(path) return not missing[path] end

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

local function fresh()
    fake.reset()
    package.loaded['nimgui.fonts'] = nil
    return require 'nimgui.fonts'
end

local fonts = fresh()

check('fonts start not ready', fonts.ready() == false)
local ok, err = fonts.push('body')
check('push before setup reports an error', ok == nil and type(err) == 'string', err)
ok, err = fonts.pop()
check('pop before setup reports an error', ok == nil and type(err) == 'string', err)

ok, err = fonts.setup()
check('setup requires options', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({})
check('setup requires base', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({ base = {} })
check('setup requires base.path', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({ base = { path = 'missing.ttf' } })
check('missing base font reports an error', ok == nil and type(err) == 'string', err)
check('missing base font adds nothing', fake.count.fontAdds == 0)
check('failed setup stays not ready', fonts.ready() == false)

fonts = fresh()
ok, err = fonts.setup({
    base = { path = 'trebucbd.ttf' },
    sizes = { body = 14, label = 11, display = 20 },
    dpi = 2,
})
check('setup succeeds with named sizes', ok == true, err)
check('ready after setup', fonts.ready() == true)
check('one atlas font per named size', #fake.fontAtlas.fonts == 3, #fake.fontAtlas.fonts)

local body, display, label = fake.fontAtlas.fonts[1], fake.fontAtlas.fonts[2], fake.fontAtlas.fonts[3]
check('names are added in sorted order', body.source == 'trebucbd.ttf')
check('body size is dpi scaled', body.size == 28, body.size)
check('display size is dpi scaled', display.size == 40, display.size)
check('label size is dpi scaled', label.size == 22, label.size)

local base_builder = body.ranges.builder
check('base ranges include cyrillic', base_builder.ranges[1] == 'cyrillic')
local extra_ok = false
for _, text in ipairs(base_builder.texts) do
    if text:find('€', 1, true) ~= nil then
        extra_ok = true
    end
end
check('base ranges include extra punctuation', extra_ok)
check('every size shares the base range pointer', body.ranges == display.ranges)
check('setup does not invalidate a fresh atlas', fake.count.fontInvalidates == 0)

ok, err = fonts.setup({ base = { path = 'other.ttf' } })
check('second setup is a no-op', ok == true and fake.count.fontAdds == 3, err)

ok, err = fonts.push('body')
check('push accepts a known size', ok == true, err)
check('push forwards the registered font', fake.pushedFonts[1] == body)
ok, err = fonts.push('nope')
check('push rejects an unknown size', ok == nil and type(err) == 'string', err)
check('unknown size does not reach the binding', #fake.pushedFonts == 1)
ok, err = fonts.pop()
check('pop reaches the binding', ok == true and fake.count.fontPops == 1, err)

fonts = fresh()
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf', size = 16 }, dpi = 1.5 })
check('base.size is used when sizes is omitted', ok == true, err)
check('omitted sizes create one body font', #fake.fontAtlas.fonts == 1)
check('default body size is dpi scaled', fake.fontAtlas.fonts[1].size == 24,
    fake.fontAtlas.fonts[1].size)
check('body name still pushes', fonts.push('body') == true)

fonts = fresh()
MONET_DPI_SCALE = 1.25
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf', size = 14 } })
check('dpi falls back to MONET_DPI_SCALE', ok == true and fake.fontAtlas.fonts[1].size == 17.5,
    err)
MONET_DPI_SCALE = 1.0

fonts = fresh()
ok, err = fonts.setup({
    base = { path = 'trebucbd.ttf' },
    sizes = { body = 14, display = 20 },
    icons = { path = 'icons.ttf', size = 14, codepoints = { 0xE005, '\xef\x80\x87' } },
    dpi = 1,
})
check('icon setup succeeds', ok == true, err)
check('icon font is merged after body', #fake.fontAtlas.fonts == 3, #fake.fontAtlas.fonts)
body, display = fake.fontAtlas.fonts[1], fake.fontAtlas.fonts[3]
local icon = fake.fontAtlas.fonts[2]
check('icon font follows the body font', icon.kind == 'file' and icon.source == 'icons.ttf')
check('icon font enables merge mode', icon.cfg ~= nil and icon.cfg.MergeMode == true)
check('icon size is dpi scaled', icon.size == 14, icon.size)
check('display font has no merge config', display.cfg == nil)
local icon_builder = icon.ranges.builder
check('numeric icon codepoints become glyph chars', icon_builder.chars[1] == 0xE005,
    icon_builder.chars[1])
check('utf-8 icon codepoints become glyph text', icon_builder.texts[1] == '\xef\x80\x87')
check('icon glyph ranges are forwarded', icon.ranges.builder == icon_builder)
check('base and icon builders are distinct', body.ranges.builder ~= icon_builder)

fonts = fresh()
ok, err = fonts.setup({
    base = { path = 'trebucbd.ttf' },
    icons = { data_base85 = 'ABC', codepoints = { 0xE005 } },
    dpi = 1,
})
check('embedded base85 icons load without a file', ok == true, err)
icon = fake.fontAtlas.fonts[2]
check('base85 icons use the memory path', icon.kind == 'base85' and icon.source == 'ABC')

fonts = fresh()
missing['icons.ttf'] = true
ok, err = fonts.setup({
    base = { path = 'trebucbd.ttf' },
    icons = { path = 'icons.ttf', codepoints = { 1 } },
})
check('missing icon font reports an error', ok == nil and type(err) == 'string', err)
check('missing icon font adds nothing', fake.count.fontAdds == 0)
missing['icons.ttf'] = nil

ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' }, icons = { path = 'icons.ttf' } })
check('icons require codepoints', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' }, icons = { codepoints = { 1 } } })
check('icons require a source', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({
    base = { path = 'trebucbd.ttf' },
    icons = { path = 'icons.ttf', codepoints = { 0x10000 } },
})
check('icons reject codepoints above 16 bits', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({
    base = { path = 'trebucbd.ttf' },
    icons = { path = 'icons.ttf', codepoints = { true } },
})
check('icons reject non-character codepoints', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' }, sizes = { body = 0 } })
check('sizes must be positive', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' }, sizes = 'body' })
check('sizes must be a table', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' }, sizes = {} })
check('sizes must not be empty', ok == nil and type(err) == 'string', err)
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' }, dpi = 0 })
check('dpi must be positive', ok == nil and type(err) == 'string', err)
check('validation failures leave the manager idle', fonts.ready() == false)

fonts = fresh()
fake.fontAtlas.TexID = {}
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' } })
check('existing texture is invalidated after setup', ok == true and fake.count.fontInvalidates == 1,
    fake.count.fontInvalidates)

fonts = fresh()
fake.fontAtlas.built = true
ok, err = fonts.setup({ base = { path = 'trebucbd.ttf' } })
check('built atlas is invalidated after setup', ok == true and fake.count.fontInvalidates == 1,
    fake.count.fontInvalidates)

print('')
print(checks .. ' checks, ' .. failures .. ' failures')
