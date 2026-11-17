-- This file is part of the nimgui project.
-- Licensed under the MIT License.
-- Copyright (c) 2026, Sena

local imgui = require 'mimgui'

local M = {}

local function require_state(state)
    if type(state) ~= 'table' then
        error('nimgui.state: state must be a table', 2)
    end
end

function M.create(state)
    require_state(state)

    local cache = {}
    local binder = { state = state }

    local function make(key, kind, default)
        if type(key) ~= 'string' then
            error('nimgui.state: key must be a string', 2)
        end
        if cache[key] then
            return cache[key]
        end

        local value = state[key]
        if value == nil then
            value = default
        end

        local cdata
        if kind == 'int' then
            cdata = imgui.new.int(value or 0)
        elseif kind == 'bool' then
            cdata = imgui.new.bool(value and true or false)
        elseif kind == 'float' then
            cdata = imgui.new.float(value or 0)
        else
            error('nimgui.state: kind must be int, bool or float', 2)
        end

        local proxy = { key = key, kind = kind }
        function proxy:get() return state[key] end
        function proxy:set(v) state[key] = v end
        function proxy:commit() state[key] = cdata[0] end
        function proxy:refresh() cdata[0] = state[key] end
        function proxy:value() return cdata[0] end
        function proxy:cdata() return cdata end

        cache[key] = proxy
        return proxy
    end

    function binder:int(key, default) return make(key, 'int', default) end
    function binder:bool(key, default) return make(key, 'bool', default) end
    function binder:float(key, default) return make(key, 'float', default) end
    function binder:get(key) return state[key] end
    function binder:set(key, value) state[key] = value end

    return binder
end

return M
