local computer = require("computer")

local uptime = computer.uptime
local rawPullSignal = computer.pullSignal
local rawPushSignal = computer.pushSignal

local eventManager = {}
local unmanagedHandlers = {}
local managedHandlers = {}
local timers = {}

eventManager.unmanagedHandlers = unmanagedHandlers
eventManager.managedHandlers = managedHandlers
eventManager.timers = timers

local function getHandlers(type)
    local types = { u = true, m = true }
    assert(types[type], "bad argument #1 (u or m expected, got " .. type .. ")")

    if type == "u" then
        return unmanagedHandlers
    elseif type == "m" then
        return managedHandlers
    end
end

local function getEventType(eventName)
    if string.match(eventName, "^%(MANAGED%)") then
        return "m"
    else
        return "u"
    end
end

local function stripManagedHeader(eventName)
    return string.gsub(eventName, "^%(MANAGED%)", "")
end

local function sortHandlersByPriority(handlers)
    local keys = {}
    for key in pairs(handlers) do
        table.insert(keys, key)
    end

    table.sort(keys, function(a, b)
        return handlers[a].priority > handlers[b].priority
    end)

    local t = {}
    setmetatable(t, {
        __index = function(t, i)
            return handlers[i]
        end,
        __newindex = function(t, i, v)
            handlers[i] = v
        end,
        __pairs = function(t)
            local i, v = nil, nil
            return function()
                i, v = next(keys, i)
                return v, handlers[v]
            end
        end
    })
    
    return t
end
-- for testing purposes only
eventManager.sort = sortHandlersByPriority

function eventManager.listen(type, name, callback, priority, error_callback)
    checkArg(1, type, "string")
    checkArg(2, name, "string", "nil")
    checkArg(3, callback, "function", "table")
    checkArg(4, priority, "number", "nil")
    checkArg(5, error_callback, "function", "nil")

    local handler = {
        name = name,
        callback = callback,
        priority = priority or 0,
        onError = error_callback
    }

    local handlers = getHandlers(type)

    for _, handler in pairs(handlers) do
        if handler.name == name and handler.callback == callback then
            return nil, "duplicate handler already exists"
        end
    end

    local event_id = 1
    repeat
        event_id = event_id + 1
    until not handlers[event_id]

    handlers[event_id] = handler
    return event_id
end

function eventManager.registerTimer(callback, interval, times, error_callback)
    checkArg(1, callback, "function", "table")
    checkArg(2, interval, "number")
    checkArg(3, times, "number", "nil")
    checkArg(4, error_callback, "function", "nil")

    local timer = {
        callback = callback,
        interval = interval,
        times = times or math.huge,
        timeout = computer.uptime() + interval,
        onError = error_callback
    }

    local timer_id = 1
    repeat
        timer_id = timer_id + 1
    until not timers[timer_id]

    timers[timer_id] = timer
    return timer_id
end

function eventManager.pull(type, timeout)
    checkArg(1, type, "string")
    checkArg(2, timeout, "number", "nil")
    timeout = timeout or math.huge
    local uptime = computer.uptime
    local deadline = uptime() + timeout

    repeat
        -- Implement interrupt logic

        -- Pull only for as long as the closest timer's timeout so that we don't miss timer wake ups
        local closest_timer = deadline
        for _, timer in pairs(timers) do
            closest_timer = math.min(timer.timeout, closest_timer)
        end

        local event_data = table.pack(rawPullSignal(closest_timer - uptime()))
        local signal = event_data[1]

        -- timer wake up logic
        for id, timer in pairs(timers) do
            if uptime() >= timer.timeout then
                timer.times = timer.times - 1
                timer.timeout = uptime() + timer.interval

                if timer.times <= 0 then
                    eventManager.unregisterTimer(id)
                end

                -- call timer
                --printk("DEBUG: eventManager: invoking timer " .. id)
                local result, message = pcall(timer.callback)
                if result and message == false then -- the timer has requested to unregister itself
                    eventManager.unregisterTimer(id)
                elseif not result then
                    pcall(timer.onError, id, message)
                end
            end
        end

        -- if we received an event then we can actually pass it to event listeners
        if signal then
            -- make sure we pass the event to the right queue
            local eventType = getEventType(signal)
            local eventName = stripManagedHeader(signal)
            event_data[1] = eventName -- replace the event name
            local handlers = getHandlers(eventType)
            --printk("DEBUG: eventManager: received event: event(\"" .. getEventType(signal) .. "\", \"" .. eventName .. "\")")
            for id, handler in pairs(sortHandlersByPriority(handlers)) do
                if handler.name == eventName then
                    --printk("DEBUG: eventManager: invoking handler " .. id)
                    local result, message, handled = pcall(handler.callback, table.unpack(event_data))
                    if result and message == false then
                        eventManager.unregisterListener(eventType, handler.name, handler.callback)
                    elseif not result then
                        pcall(handler.onError, id, message)
                    end
                    
                    if result and handled == true then
                        break -- event state set to handled
                    end
                end
            end

            if type == eventType then
                return table.unpack(event_data)
            end
        end
    until uptime() >= deadline
end

function eventManager.push(type, eventName, ...)
    checkArg(1, type, "string")
    checkArg(2, eventName, "string")

    if type == "m" then
        eventName = "(MANAGED)" .. eventName
    end

    return rawPushSignal(eventName, ...)
end

function eventManager.unregisterListener(type, eventName, callback)
    checkArg(1, type, "string")
    checkArg(2, eventName, "string")
    checkArg(3, callback, "function")

    local handlers = getHandlers(type)
    for eventId, handler in pairs(handlers) do
        if handler.name == eventName and handler.callback == callback then
            handlers[eventId] = nil
            return true
        end
    end

    return false
end

function eventManager.unregisterTimer(timerId)
    checkArg(1, timerId, "number")

    if not timers[timerId] then
        return false
    end

    timers[timerId] = nil
    return true
end

function eventManager.getPriority(type, eventName, callback)
    checkArg(1, type, "string")
    checkArg(2, eventName, "string")
    checkArg(3, callback, "function")

    local handlers = getHandlers(type)
    for _, handler in pairs(handlers) do
        if handler.name == eventName and handler.callback == callback then
            return handler.priority
        end
    end

    return nil, "Event not found"
end

function eventManager.setPriority(type, eventName, callback, priority)
    checkArg(1, type, "string")
    checkArg(2, eventName, "string")
    checkArg(3, callback, "function")
    checkArg(4, priority, "number")

    local handlers = getHandlers(type)
    for _, handler in pairs(handlers) do
        if handler.name == eventName and handler.callback == callback then
            handler.priority = priority
            return true
        end
    end

    return nil, "Event not found"
end

return eventManager