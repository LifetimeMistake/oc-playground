local eventManager = require("eventManager")
local computer = require("computer")

local event = {}
local lastInterrupt = -math.huge

function event.register(eventName, callback, interval, times, opt_handlers)
    checkArg(1, eventName, "string", "boolean", "nil")
    checkArg(2, callback, "function")
    checkArg(3, interval, "number", "nil")
    checkArg(4, times, "number", "nil")
    checkArg(5, opt_handlers, "table", "nil")

    if eventName then
        -- handler
        return eventManager.listen("m", eventName, callback, nil, event.onError)
    else
        -- timer
        return eventManager.registerTimer(callback, interval, times, event.onError)
    end
end

function event.createPlainFilter(eventName, ...)
    local filter = table.pack(...)
    if filter.n == 0 then
        return nil
    end
end

function event.createMultipleFilter(...)
    local filter = table.pack(...)
    if filter.n == 0 then
        return nil
    end

    return function(...)
        local signal = table.pack(...)
        if type(signal[1]) ~= "string" then
            return false
        end
        for i = 1, filter.n do
            if filter[i] ~= nil and signal[1]:match(filter[i]) then
            return true
            end
        end
        return false
        end
end

function event.listen(eventName, callback)
    checkArg(1, eventName, "string")
    checkArg(2, callback, "function")
    return event.register(eventName, callback, math.huge, math.huge)
end

function event.timer(interval, callback, times)
    checkArg(1, interval, "number")
    checkArg(2, callback, "function")
    checkArg(3, times, "number", "nil")
    return event.register(false, callback, interval, times)
end

function event.pull(...)
    local args = table.pack(...)
    if type(args[1]) == "string" then
        return event.pullFiltered(event.createPlainFilter(...))
    else
         checkArg(1, args[1], "number", "nil")
        checkArg(2, args[2], "string", "nil")
        return event.pullFiltered(args[1], event.createPlainFilter(select(2, ...)))
    end
end

function event.pullFiltered(...)
    local args = table.pack(...)
    local seconds, filter = math.huge, nil
  
    if type(args[1]) == "function" then
        filter = args[1]
    else
        checkArg(1, args[1], "number", "nil")
        checkArg(2, args[2], "function", "nil")
        seconds = args[1]
        filter = args[2]
    end

    repeat
        local signal = table.pack(computer.pullSignal(seconds))
        if signal.n > 0 then
            if not (seconds or filter) or filter == nil or filter(table.unpack(signal, 1, signal.n)) then
                return table.unpack(signal, 1, signal.n)
            end
        end
    until signal.n == 0
end

function event.pullMultiple(...)
    local seconds
    local args
    if type(...) == "number" then
        seconds = ...
        args = table.pack(select(2,...))
        for i=1,args.n do
            checkArg(i+1, args[i], "string", "nil")
        end
    else
        args = table.pack(...)
        for i=1,args.n do
            checkArg(i, args[i], "string", "nil")
        end
    end
    return event.pullFiltered(seconds, event.createMultipleFilter(table.unpack(args, 1, args.n)))
end

function event.ignore(eventName, callback)
    checkArg(1, eventName, "string")
    checkArg(2, callback, "function")
    return eventManager.unregisterListener("m", eventName, callback)
end

function event.cancel(timerId)
    checkArg(1, timerId, "number")
    return eventManager.unregisterTimer(timerId)
end

function event.onError(id, message)
    local log = io.open("/event.log", "a")
    if log then
        pcall(log.write, log, tostring(message), "\n")
        log:close()
    end
end

function computer.pullSignal(seconds)
    -- Wrap managed event calls
    -- local result = table.pack(eventManager.pull("m", seconds))
    -- if not result[1] and result[2] then
    --     pcall(event.onError, result[2])
    --     table.remove(result, 1)
    --     table.remove(result, 1)
    -- end

    -- return table.unpack(result)
    return eventManager.pull("m", seconds)
end

function computer.pushSignal(eventName, ...)
    -- Wrap managed event calls
    return eventManager.push("m", eventName, ...)
end

event.push = computer.pushSignal

return event
-- Obecnie jestem w stegnie na plaży