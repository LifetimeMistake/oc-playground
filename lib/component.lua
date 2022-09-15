local component = {}
local componentManager = require("componentManager")
local primaries = {}

setmetatable(component, {
    __index = function(_, key)
        return component.getPrimary(key)
    end,
    __pairs = function(self)
        local parent = false
        return function(_, key)
            if parent then
                return next(primaries, key)
            else
                local k, v = next(self, key)
                if not k then
                    parent = true
                    return next(primaries)
                else
                    return k, v
                end
            end
        end
    end
})

function component.doc(address, method)
    checkArg(1, address, "string")
    checkArg(2, method, "string")

    local data, message = componentManager.getDocs(address, method)
    return data or ""
end

function component.type(address)
    checkArg(1, address, "string")

    local component = componentManager.getComponent(address)
    if not component then
        return nil, "no such component"
    end

    return component.type
end

function component.slot(address)
    checkArg(1, address, "string")

    local component = componentManager.getComponent(address)
    if not component then
        return nil, "no such component"
    end

    return component.slot
end

function component.methods(address)
    checkArg(1, address, "string")

    local component = componentManager.getComponent(address)
    if not component then
        return nil, "no such component"
    end

    local methods = {}
    for name,func in pairs(component.methods) do
        methods[name] = true
    end

    return methods
end

-- Not sure what this is supposed to return, this function is not documented anywhere
-- this is what I imagine it should look like
function component.fields(address)
    checkArg(1, address, "string")

    local component = componentManager.getComponent(address)
    if not component then
        return nil, "no such component"
    end

    local fields = {}
    for k,v in pairs(component.fields) do
        fields[k] = v
    end

    return fields
end

function component.invoke(address, method, ...)
    checkArg(1, address, "string")
    checkArg(2, method, "string")

    if not componentManager.componentExists(address) then
        error("no such component")
    end

    local result = table.pack(componentManager.invoke(address, method, ...))
    if not result[1] then
        error("no such method")
    end

    table.remove(result, 1)
    return table.unpack(result)
end

function component.isAvailable(componentType)
    checkArg(1, componentType, "string")
    return componentManager.isAvailable(componentType)
end

function component.list(filter, exact)
    checkArg(1, filter, "string", "nil")
    checkArg(2, exact, "boolean", "nil")

    local components = {}
    for component in componentManager.listComponents() do
        if (exact and component.type == filter) or (not exact and string.find(component.type, filter)) then
            components[component.address] = component.type
        end
    end

    local k,v 

    setmetatable(components, {
        __call = function(t, ...)
            k, v = next(components, k)
            return k, v
        end
    })

    return components
end

function component.proxy(address)
    checkArg(1, address, "string")
    local component, message = componentManager.getComponent(address)
    if not component then
        return nil, "no such component"
    end

    local proxy = {}
    -- proxy fields
    for k,v in pairs(component.fields) do
        proxy[k] = v
    end

    -- proxy methods
    for k,v in pairs(component.methods) do
        proxy[k] = v
    end

    -- we set these at the end to prevent any mischevious functions from overriding the 4 mandatory fields
    proxy.address = component.address
    proxy.type = component.type
    proxy.slot = component.slot
    proxy.ownerModule = component.ownerModule
    return proxy
end

function component.get(address, componentType)
    checkArg(1, address, "string")
    checkArg(2, componentType, "string", "nil")

    for component in componentManager.listComponents() do
        if string.sub(component.address, 1, string.len(address)) == address 
        and (not componentType or component.type == componentType) then
            return component.address
        end
    end

    -- how even?
    return {}
end

function component.getPrimary(componentType)
    checkArg(1, componentType, "string")
    if not primaries[componentType] then
        error("no primary '" .. componentType .. "' available")
    end

    return primaries[componentType]
end

function component.setPrimary(componentType, address)
    checkArg(1, componentType, "string")
    checkArg(2, address, "string")
    local proxy, message = component.proxy(address)
    if not proxy then
        error(message)
    end
    -- hi mom
    primaries[componentType] = proxy
end

return component