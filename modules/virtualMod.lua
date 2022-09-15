-- This driver emulates a redstone card
local MODULE_NAME = "virtual-redstone"
local sides = require("sides")
local eventManager = require("eventManager")
local componentManager = require("componentManager")
local address = "wow-look-at-me-i-can-input-anything-i-want-here"

local inputLevels = {
    [sides.front] = 0,
    [sides.back] = 0,
    [sides.left] = 0,
    [sides.right] = 0,
    [sides.top] = 0,
    [sides.bottom] = 0,
    [sides.unknown] = 0
}

local outputLevels = {
    [sides.front] = 0,
    [sides.back] = 0,
    [sides.left] = 0,
    [sides.right] = 0,
    [sides.top] = 0,
    [sides.bottom] = 0,
    [sides.unknown] = 0
}

local function setOutput(side, value)
    local oldValue = outputLevels[side]
    outputLevels[side] = value
    return oldValue
end

local function getOutput(side)
    return outputLevels[side]
end

local function getInput(side)
    return inputLevels[side]
end

local function setInput(side, value)
    local oldValue = inputLevels[side]
    inputLevels[side] = value
    eventManager.push("m", "redstone_changed", address, side, oldValue, value)
    return oldValue
end

local function init()
    local component = {
        address = address,
        type = "redstone",
        slot = -1,
        ownerModule = MODULE_NAME,
        methods = {
            getInput = getInput,
            getOutput = getOutput,
            setInput = setInput,
            setOutput = setOutput
        },
        fields = {},
        doc = function() return "" end
    }
    local result, message = componentManager.registerComponent(component)
    if not result then
        printk("Failed to register virtual device: " .. message)
    end
    return true
end

local function destroy()
    componentManager.removeComponent(address)
end

return function(module)
    module.name = MODULE_NAME
    module.description = "This module emulates a subset of the features provided by a redsdtone card"
    module.module_init = init
    module.module_destroy = destroy
    return true
end