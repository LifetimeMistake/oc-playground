local package = {}
package.path = "/boot/kernel/?.lua;/boot/kernel/?/init.lua;/boot/lib/?.lua;/boot/lib/?/init.lua;/lib/?.lua;/usr/lib/?.lua;./?.lua;/lib/?/init.lua;/usr/lib/?/init.lua;/home/lib/?/init.lua;./?/init.lua"
local loading = {}
local loaded = {
    _G = _G,
    bit32 = bit32,
    coroutine = coroutine,
    math = math,
    os = os,
    package = package,
    string = string,
    table = table
}

package.loaded = loaded

function package.searchpath(name, path, sep, rep)
    checkArg(1, name, "string")
    checkArg(2, path, "string")
    
    sep = sep or '.'
    rep = rep or '/'
    sep, rep = '%' .. sep, rep
    name = string.gsub(name, sep, rep)

    local fs = require("filesystem")
    local errorFiles = {}
    for subPath in string.gmatch(path, "([^;]+)") do
        subPath = string.gsub(subPath, "?", name)
        if subPath:sub(1, 1) ~= "/" and os.getenv then
            subPath = fs.concat(os.getenv("PWD") or "/", subPath)
        end

        if fs.exists(subPath) then
            local file = fs.open(subPath, "r")
            if file then
                file:close()
                return subPath
            end
        end

        table.insert(errorFiles, "\tno file '" .. subPath .. "'")
    end

    return nil, table.concat(errorFiles, "\n")
end

function require(module, reload)
    checkArg(1, module, "string")
    checkArg(2, reload, "boolean", "nil")

    if loaded[module] ~= nil and not reload then
        return loaded[module]
    elseif not loading[module] then
        local library, status, step
        step, library, status = "not found", package.searchpath(module, package.path)

        if library then
            step, library, status = "loadfile failed", loadfile(library)
        end

        if library then
            loading[module] = true
            step, library, status = "load failed", pcall(library, module)
            loading[module] = false
        end

        assert(library, string.format("module '%s' %s:\n%s", module, step, status))
        loaded[module] = status
        return status
    else
        error("already loading: " .. module .. "\n" .. debug.traceback(), 2)
    end
end

function package.delay(lib, file)
    local protect = require("protect")
    if protect.isreadonly(lib) or protect.isreadonly(lib.internal) then
        return nil, "Cannot delay load into a protected memory region"
    end

    local mt = {}
    function mt.__index(tbl, key)
        mt.__index = nil
        dofile(file)
        return tbl[key]
    end

    if lib.internal then
        setmetatable(lib.internal, mt)
    end

    setmetatable(lib, mt)
end

return package