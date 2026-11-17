-- headless checks for dist/lib/motion.lua
-- run: luajit tests/test_motion.lua

local root = arg[0]:gsub('\\', '/'):match('^(.*)/tests/[^/]+$') or '.'
local motion = dofile(root .. '/dist/lib/motion.lua')

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

-- tracker moves monotonically toward the target and never overshoots
local tr = motion.tracker(0.08)
tr:step('seg', 0, 0.016)
local previous = 0
local monotonic = true
local overshoot = false
for _ = 1, 60 do
  local value = tr:step('seg', 1, 1 / 60)
  if value < previous - 1e-9 then monotonic = false end
  if value > 1.000001 then overshoot = true end
  previous = value
end
check('tracker is monotonic', monotonic)
check('tracker does not overshoot', not overshoot)
check('tracker converges on the target', math.abs(previous - 1) < 0.005, previous)

-- frame rate independence: same elapsed time, different step size
local a = motion.tracker(0.08)
a:step('x', 0, 0.016)
for _ = 1, 30 do a:step('x', 1, 1 / 60) end

local b = motion.tracker(0.08)
b:step('x', 0, 0.016)
for _ = 1, 15 do b:step('x', 1, 1 / 30) end

check('30 frames at 60fps match 15 frames at 30fps', math.abs(a:step('x', 1, 0.016) - b:step('x', 1, 0.016)) < 0.01,
  a:step('x', 1, 0.016) .. ' vs ' .. b:step('x', 1, 0.016))

-- a huge dt jumps straight to the target
local c = motion.tracker(0.08)
c:step('y', 0, 0.016)
check('large dt lands on the target', math.abs(c:step('y', 1, 5) - 1) < 0.001, c:step('y', 1, 5))

-- easing stays inside 0..1
local inside = true
for i = 0, 20 do
  local t = i / 20
  local v = motion.ease.out_cubic(t)
  if v < 0 or v > 1 then inside = false end
end
check('out_cubic stays inside 0..1', inside)

check('clamp01 clamps high', motion.clamp01(2) == 1)
check('clamp01 clamps low', motion.clamp01(-1) == 0)

print(string.format('\n%d checks, %d failures', checks, failures))
os.exit(failures == 0 and 0 or 1)
