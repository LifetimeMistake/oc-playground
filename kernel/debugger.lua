local debugger = {}

function debugger.serializeTable(t)
    local entries = {}
    for k,v in pairs(t) do
        if checkType(v, "string") then
            v = "\"" .. v .. "\""
        else
            v = tostring(v)
        end

        table.insert(entries, k .. " = " .. v)
    end

    return "{ " .. table.concat(entries, ", ") .. " }"
end

function debugger.generateArgs(...)
    local args = {}
    for i, arg in ipairs(table.pack(...)) do
        if checkType(arg, "string") then
            arg = "\"" .. arg .. "\""
        elseif checkType(arg, "table") then
            arg = debugger.serializeTable(arg)
        else
            arg = tostring(arg)
        end

        table.insert(args, arg)
    end

    return table.concat(args, ", ")
end

function debugger.generateFunctionCallDescription(tableName, functionName, args, returnValues)
    return tableName .. "." .. functionName .. "(" .. debugger.generateArgs(table.unpack(args)) .. "): " .. debugger.generateArgs(table.unpack(returnValues or {}))
end

function debugger.generateFieldReadDescription(tableName, fieldName, value)
    return tableName .. "." .. fieldName .. ": " .. tostring(value)
end

function debugger.generateFieldWriteDescription(tableName, fieldName, oldValue, newValue)
    return tableName .. "." .. fieldName .. " = " .. tostring(newValue) .. " (was " .. tostring(oldValue) .. ")"
end

function debugger.generateTableCallDescription(tableName, args, returnValues)
    return tableName .. "(" .. debugger.generateArgs(table.unpack(args)) .. "): " .. debugger.generateArgs(table.unpack(returnValues or {}))
end

function debugger.attach(tbl, tName, options, callback)
    checkArg(1, tbl, "table")
    checkArg(2, options, "table")
    checkArg(3, callback, "function")

    local _rawget = rawget
    local _rawset = rawset
    local original_mt = _rawget(tbl, "__metatable")

    local info = {
        original_mt = original_mt,
        original_tbl = tbl,
        options = options
    }

    local mt = {}

    if original_mt then
        mt.__metatable = original_mt.__metatable
    end

    local proxy = {
        __debugger = info
    }

    if options.hook_index then
        mt.__index = function(t, k)
            local value = tbl[k]

            -- raise the index event
            callback(tbl, tName, "index", k, value)

            if options.proxy_function_calls and checkType(value, "function") then
                -- generate a proxy
                return function(...)
                    local returnValues = table.pack(value(...))
                    -- raise the proxy_call event
                    callback(tbl, tName, "proxy_call", k, table.pack(...), returnValues)
                    return table.unpack(returnValues)
                end
            end

            return value
        end
    end

    if options.hook_newindex then
        mt.__newindex = function(t, k, newValue)
            local oldValue = tbl[k]

            -- raise the newindex event
            callback(tbl, tName, "newindex", k, oldValue, newValue)

            tbl[k] = newValue
        end
    end

    if options.hook_call and original_mt and original_mt.__call then
        mt.__call = function(t, ...)
            -- raise the call event
            local returnValues = table.pack(tbl(...))
            callback(tbl, tName, "call", table.pack(...), returnValues)

            -- metatable passthrough
            return table.unpack(returnValues)
        end
    end

    return setmetatable(proxy, mt)
end

function debugger.detach(t)
    if not checkType(t, "table") or not t.__debugger then
        return nil, "table does not have a debugger attached"
    end 

    return t.__debugger.original_tbl
end

return debugger