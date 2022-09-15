local protect = {}
protect.rawgetmetatable = getmetatable
protect.rawsetmetatable = setmetatable

function protect.setreadonly(table, enforcing)
    checkArg(1, table, "table")
    checkArg(2, enforcing, "boolean", "nil")

    local t = {}
    local mt = {
        __index = function(t,k)
            return table[k]
        end,
        __newindex = function(t,k,v)
            if enforcing then
                error("Attempted to write to a protected table (enforcing mode)")
            else
                printk(debug.traceback("Warning: Attempted to write to a protected table (permissive mode)"))
            end
        end,
        __metatable = "protected"
    }

    setmetatable(t, mt)
    return t
end

function protect.isreadonly(table)
    return type(table) == "table" and getmetatable(table) == "protected"
end

function getmetatable(object)
    local mt = protect.rawgetmetatable(object)
    return mt
end

function setmetatable(t, object)
    if getmetatable(object) == "protected" then
        return nil
    end

    return protect.rawsetmetatable(t, object)
end

return protect