-- motion.lua
-- Frame-rate independent motion helpers for mimgui panels.
-- dt and time are supplied by the caller so the curves can be tested headless.

local M = {}

M.ease = {
    linear = function(t) return t end,
    out_cubic = function(t) return 1 - (1 - t) ^ 3 end,
    in_out_cubic = function(t)
        if t < 0.5 then return 4 * t * t * t end
        return 1 - (-2 * t + 2) ^ 3 / 2
    end,
    out_back = function(t)
        local c1, c3 = 1.70158, 2.70158
        return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
    end,
}

function M.approach(current, target, tau, dt)
    return target + (current - target) * math.exp(-dt / tau)
end

function M.clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

function M.progress(now, start, duration, delay)
    return M.clamp01((now - start - (delay or 0)) / duration)
end

function M.stagger(index, step)
    return (index - 1) * step
end

function M.lerp(a, b, t) return a + (b - a) * t end

local Tracker = {}
Tracker.__index = Tracker

function M.tracker(tau)
    return setmetatable({ tau = tau, values = {} }, Tracker)
end

function Tracker:step(id, target, dt)
    local current = self.values[id]
    if current == nil then
        self.values[id] = target
        return target
    end
    if math.abs(current - target) < 0.001 then
        self.values[id] = target
        return target
    end
    current = M.approach(current, target, self.tau, dt)
    self.values[id] = current
    return current
end

return M
