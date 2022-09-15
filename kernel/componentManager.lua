local eventManager = require("eventManager")
local components = {}
local componentManager = {}
componentManager.rawComponent = require("component") -- this should be set by the bootloader

function componentManager.registerComponent(component)
    checkArg(1, component, "table")

    if not checkType(component.address, "string")
    or not checkType(component.type, "string")
    or not checkType(component.slot, "number")
    or not checkType(component.ownerModule, "string") 
    or not checkType(component.methods, "table") 
    or not checkType(component.fields, "table")
    or not checkType(component.doc, "function") then
        return nil, "Invalid/corrupt component struct"
    end

    if componentManager.componentExists(component.address) then
        return nil, "Component with address " .. component.address .. " already exists"
    end

    components[component.address] = component
    eventManager.push("m", "component_added", component.address, component.type)
    return true
end

function componentManager.removeComponent(address)
    checkArg(1, address, "string")

    local component, message = componentManager.getComponent(address)
    if not component then
        return nil, message
    end

    components[component.address] = nil
    eventManager.push("m", "component_removed", component.address, component.type)
    return true
end

function componentManager.getDocs(address, method)
    checkArg(1, address, "string")
    checkArg(2, method, "string")

    local component, message = componentManager.getComponent(address) 
    if not component then
        return nil, message
    end

    local result, data = pcall(component.doc, method)
    if not result then
        return nil, "Method call failed: " .. data
    end

    return data
end

function componentManager.getComponent(address)
    checkArg(1, address, "string")

    if not componentManager.componentExists(address) then
        return nil, "Component with address " .. address .. " does not exist"
    end

    return components[address]
end

function componentManager.componentExists(address)
    checkArg(1, address, "string")
    return components[address] ~= nil
end

function componentManager.invoke(address, func, ...)
    checkArg(1, address, "string")
    checkArg(2, func, "string")
    
    local component, message = componentManager.getComponent(address)
    if not component then
        return false, message
    end

    if not component.methods[func] then
        return false, "Failed to invoke method: Method does not exist"
    end

    return true, table.unpack(component.methods[func](...))
end

function componentManager.isAvailable(componentType)
    for component in componentManager.listComponents() do
        if component.type == componentType then
            return true
        end
    end

    return false
end

function componentManager.listComponents()
    local i, v = nil, nil
    return function()
        i, v = next(components, i)
        return v
    end
end

return componentManager