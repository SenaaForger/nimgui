-- headless checks for dist/lib/color.lua
-- run: luajit tests/test_color.lua

local color = dofile((arg[0]:gsub('\\', '/'):match('^(.*)/tests/[^/]+$') or '.') .. '/dist/lib/color.lua')

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

local P = color.palette({ hue = 215, tint = 0.14, accentHue = 40, accentSat = 0.75, accentLight = 0.62 })

check('text on bg >= 4.5', color.contrast(P.text, P.bg) >= 4.5, color.contrast(P.text, P.bg))
check('muted on raised >= 4.5', color.contrast(P.muted, P.raised) >= 4.5, color.contrast(P.muted, P.raised))
check('muted on surface >= 4.5', color.contrast(P.muted, P.surface) >= 4.5, color.contrast(P.muted, P.surface))
check('accent on bg >= 3', color.contrast(P.accent, P.bg) >= 3, color.contrast(P.accent, P.bg))
check('on accent on accent >= 4.5', color.contrast(P.onAccent, P.accent) >= 4.5, color.contrast(P.onAccent, P.accent))
check('success on raised >= 4.5', color.contrast(P.success, P.raised) >= 4.5, color.contrast(P.success, P.raised))
check('danger on raised >= 4.5', color.contrast(P.danger, P.raised) >= 4.5, color.contrast(P.danger, P.raised))
check('raised is lighter than surface', color.luminance(P.raised) > color.luminance(P.surface))
check('surface is lighter than bg', color.luminance(P.surface) > color.luminance(P.bg))

-- packed conversion order: 0xAABBGGRR
local packed_red = color.rgb(0xFF0000, 255)
check('rgb packs red into the low byte', packed_red % 0x100 == 0xFF, packed_red % 0x100)
check('rgb packs blue into the high color byte', math.floor(packed_red / 0x10000) % 0x100 == 0x00,
  math.floor(packed_red / 0x10000) % 0x100)
local packed_blue = color.rgb(0x0000FF, 255)
check('rgb packs blue into the high color byte', math.floor(packed_blue / 0x10000) % 0x100 == 0xFF,
  math.floor(packed_blue / 0x10000) % 0x100)
check('rgb keeps alpha in the top byte', math.floor(packed_red / 0x1000000) == 255, math.floor(packed_red / 0x1000000))

-- mix is a straight interpolation
local mid = color.mix(0x000000, 0xFFFFFF, 0.5)
check('mix halfway lands in the middle', math.abs(color.luminance(mid) - color.luminance(0x808080)) < 0.02,
  color.luminance(mid))

print(string.format('\n%d checks, %d failures', checks, failures))
os.exit(failures == 0 and 0 or 1)
