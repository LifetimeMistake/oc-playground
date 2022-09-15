-- Inject kernel data here
local function initKernel()
    local sources = {
        require = "function require(module) print(\"asked for: \" .. module); return 0 end",
        test = "test = {}; function test.aaa() return \"bruh\" end; return test",
        main = "function main() aaa() end"
    }
    
    local kernel_env = {}

    for k,v in pairs(sources) do
        kernel_env[k] = load(v)
    end

    return kernel_env["main"]
end

local init
local component_invoke = component.invoke
local function invoke(address, method, ...)
    local result = table.pack(pcall(component_invoke, address, method, ...))
    if not result[1] then
        return nil, result[2]
    else
        return table.unpack(result, 2, result.n)
    end
end

local eeprom = component.list("eeprom")()
computer.getBootAddress = function()
    return invoke(eeprom, "getData")
end

computer.setBootAddress = function(address)
    return invoke(eeprom, "setData")
end

do
    local screen = component.list("screen")()
    local gpu = component.list("gpu")()
    if gpu and screen then
        invoke(gpu, "bind", screen)
    end
end
