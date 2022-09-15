local EVENT_LIST = {
    -- computer
    "term_available",
    "term_unavailable",
    -- screen
    "screen_resized",
    "touch",
    "drag",
    "drop",
    "scroll",
    "walk",
    -- keyboard
    "key_down",
    "key_up",
    "clipboard",
    -- redstone card
    "redstone_changed",
    -- motion sensor
    "motion",
    -- network card
    "modem_message",
    -- robot
    "inventory_changed",
    -- bus card
    "bus_message",
    -- carriage
    "carriage_moved"
}

local MODULE_NAME = "autoreg"
local componentManager = require("componentManager")
local eventManager = require("eventManager")

local function component_added(eventName, address, componentType)
    local proxy = componentManager.rawComponent.proxy(address)

    local component = {
        address = address,
        type = componentType,
        slot = componentManager.rawComponent.slot(address) or -1,
        ownerModule = MODULE_NAME,
        methods = {},
        fields = {},
        doc = function(method) return componentManager.rawComponent.doc(address, method) end
    }

    for method in pairs(componentManager.rawComponent.methods(address)) do
        component.methods[method] = proxy[method]
    end

    local result, message = componentManager.registerComponent(component)
    if not result then
        printk("Failed to auto-register component: " .. message)
        return true, false -- maybe someone else can handle it
    end

    printk("Component registered of type " .. component.type .. ", address: " .. component.address)
    return true, true
end

local function component_removed(_, address, componentType)
    if not componentManager.componentExists(address) then
        return true
    end

    componentManager.removeComponent(address)
    return true, true
end

local function eventHandler(eventName, ...)
    eventManager.push("m", eventName, ...)
    return true, true
end

local function eventError(_, message)
    printk(message)
end

local function init()
    eventManager.listen("u", "component_added", component_added, -math.huge, eventError)
    eventManager.listen("u", "component_removed", component_removed, -math.huge, eventError)
    for k,v in ipairs(EVENT_LIST) do
        eventManager.listen("u", v, eventHandler, -math.huge, eventError)
    end
    printk("loaded")
    return true
end

local function destroy()
    eventManager.unregisterListener("u", "component_added", component_added)
    eventManager.unregisterListener("u", "component_removed", component_removed)
    for k,v in ipairs(EVENT_LIST) do
        eventManager.unregisterListener("u", v, eventHandler)
    end
    printk("unloaded")
    return true
end

return function(module)
    module.name = MODULE_NAME
    module.description = "auto draivir booster punjabi no virus"
    module.author = "GreatLolz"
    module.version = "1.0"
    module.module_init = init
    module.module_destroy = destroy
    return true
end