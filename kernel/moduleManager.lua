require("checkType")
local loadedModules = {}
local moduleManager = {}

-- Loads module using the provided arbitrary loader function and environment
-- probably dangerous/error-prone if exposed as a public API method
function moduleManager.load(moduleLoader, unloadable, moduleEnv)
    checkArg(1, moduleLoader, "function")
    checkArg(2, unloadable, "boolean", "nil")
    checkArg(3, moduleEnv, "table", "nil")

    local _unloadable = true
    local _moduleEnv = moduleEnv or _ENV

    if unloadable ~= nil then
        _unloadable = unloadable
    end
 
    -- Module struct template
    -- The loader is supposed to fill out the fields in this struct
    local module = {
        name = "",
        description = "",
        author = "",
        version = "",
        module_init = nil,
        module_destroy = nil,
        unloadable = _unloadable,
        environment = _moduleEnv
    }

    local result, data = moduleLoader(module)
    if not result then
        return nil, "Module loader error: " .. data
    end

    -- if else if else
    if not (checkType(module.name, "string") and #module.name > 0)
    or not checkType(module.description, "string")
    or not checkType(module.author, "string")
    or not checkType(module.version, "string")
    or not checkType(module.module_init, "function")
    or not (module.module_destroy == nil or checkType(module.module_destroy, "function"))
    or not checkType(module.unloadable, "boolean")
    or not checkType(module.environment, "table")
    or module.environment ~= _moduleEnv then
        return nil, "Module struct corruption"
    end

    if moduleManager.isLoaded(module.name) then
        return nil, "Module with name \"" .. module.name .. "\" is already loaded"
    end

    local result, message = module.module_init()
    if not result then
        return nil, "Module init failed: " .. (message or "<unknown error>")
    end

    loadedModules[module.name] = module
    return module
end

-- Loads module from disk by file path
function moduleManager.loadfile(path, unloadable, moduleEnv)
    checkArg(1, path, "string")

    local fs = require("filesystem")
    if not fs.exists(path) then
        return nil, "Specified file does not exist"
    end

    local handle, message = fs.open(path, "r")
    if not handle then
        return nil, "Failed to open file: " .. message
    end

    local script = ""
    
    while true do
        local data, message = handle:read(1024)
        if not data then
            handle:close()
            if message then
                return nil, "Failed to read file: " .. message
            end

            break
        end

        script = script .. data
    end

    return moduleManager.loadchunk(script, unloadable, moduleEnv)
end

-- Compiles a lua text chunk and builds a 
function moduleManager.loadchunk(chunk, unloadable, moduleEnv)
    checkArg(1, chunk, "string")
    checkArg(3, moduleEnv, "table", "nil")

    local _moduleEnv = moduleEnv or _ENV

    local result, message = load(chunk, "module", "t", _moduleEnv)
    if not result then
        return nil, "Failed to compile module: " .. (message or "<unknown error>")
    end

    local loader = result()

    if not checkType(loader, "function") then
        return nil, "Invalid/corrupted module image"
    end

    return moduleManager.load(loader, unloadable, _moduleEnv)
end

function moduleManager.unload(moduleName, force)
    checkArg(1, moduleName, "string")
    checkArg(2, force, "boolean", "nil")
    local _force = false

    if force ~= nil then
        _force = force
    end

    local module, message = moduleManager.getModule(moduleName)

    if not module then
        return nil, message
    end

    if not module.unloadable and not _force then
        return nil, "Specified module is not unloadable"
    end

    -- Try to perform a graceful unload
    if checkType(module.module_destroy, "function") then
        local result, message = module.module_destroy()
        if not result and not _force then
            return nil, "Failed to unload module: " .. (message or "<unknown error>")
        end
    end
    
    loadedModules[moduleName] = nil
    return true
end

function moduleManager.getModule(moduleName)
    checkArg(1, moduleName, "string")
    local module = loadedModules[moduleName]

    if not module then
        return nil, "Module with name " .. moduleName .. " does not exist"
    end

    return module
end

function moduleManager.listModules()
    local i, v = nil, nil
    return function()
        i, v = next(loadedModules, i)
        return v
    end
end

function moduleManager.isLoaded(moduleName)
    return loadedModules[moduleName] ~= nil
end

return moduleManager