local openOS_keyword = "OpenOS"
local invoke = component.invoke
local screenWidth, screenHeight, screen, gpu

local function output_init()
    local screen = component.list("screen", true)()
    local gpu = component.list("gpu", true)()
    if gpu then
        gpu = component.proxy(gpu)
    end

    if not gpu.getScreen() then
        gpu.bind(screen)
    end

    screenWidth, screenHeight = gpu.maxResolution()
    gpu.setResolution(screenWidth, screenHeight)
    gpu.setBackground(0x000000)
    gpu.setForeground(0xffffff)
    gpu.fill(1, 1, screenWidth, screenHeight, " ")

    _G.boot_screen = gpu.getScreen()
end

local printk_y = 1
function printk(message)
    if gpu then
        gpu.set(1, y, message)
        if y == screenHeight then
            gpu.copy(1, 2, screenWidth, screenHeight - 1, 0, -1)
            gpu.fill(1, screenHeight, screenWidth, 1, " ")
        else
            printk_y = printk_y + 1
        end
    end
end

local function loadfile(address, file)
    local handle = assert(invoke(address, "open", file))
    local buffer = ""

    repeat
        local data = invoke(address, "read", handle, math.huge)
        buffer = buffer .. (data or "")
    until not data

    invoke(address, "close", handle)
    return load(buffer, "=" .. file, "bt", _G)
end

local function dofile(address, file)
    printk("Loading file: " .. file)
    local program, reason = loadfile(address, file)
    if program then
        local result = table.pack(pcall(program))
        if result[1] then
            return table.unpack(result, 2, result.n)
        else
            error(result[2])
        end
    else
        error(reason)
    end
end

local function loadKernelAPI(path)
    printk("Loading kernel section: " .. path)
    return require(path, true)
end

local function protectKernelAPI(api, enforcing)
    printk("Protecting memory: " .. tostring(api) .. ", enforcing = " .. tostring(enforcing))
    local protect = require("protect")
    if not protect.isreadonly(api) then
        return protect.setreadonly(api, enforcing)
    else
        return api
    end
end

local function onDebugger(tbl, tblName, event, ...)
    local debugger = require("debugger")
    local event_data = table.pack(...)
    if event == "call" then
        printk("(TRACE) call: " .. debugger.generateTableCallDescription(tblName, event_data[2], event_data[3]))
    elseif event == "proxy_call" then
        printk("(TRACE) call: " .. debugger.generateFunctionCallDescription(tblName, event_data[1], event_data[2], event_data[3]))
    elseif event == "index" then
        printk("(TRACE) read: " .. debugger.generateFieldReadDescription(tblName, event_data[1], event_data[2]))
    elseif event == "newindex" then
        printk("(TRACE) write: " .. debugger.generateFieldWriteDescription(tblName, event_data[1], event_data[2], event_data[3]))
    end
end

local function openOS_loader(received_args)
    local openOS_address = received_args.openOS_address
    local kernel_address = received_args.kernel_address

    -- Store the native libraries
    local _component = component
    local _computer = computer
    local _unicode = unicode

    printk("== BEGIN KERNEL INIT ==")

    -- Initialize the package library
    local package = dofile(kernel_address, "/kernel/package.lua")
    dofile(kernel_address, "/kernel/base.lua")

    -- Unclutter global namespace, programs should use the require() function
    _G.component = nil
    _G.computer = nil
    _G.process = nil
    _G.unicode = nil
    _G.package = package

    -- Inject libraries into the package library
    package.loaded.component = _component
    package.loaded.computer = _computer
    package.loaded.unicode = _unicode
    package.loaded.protect = dofile(kernel_address, "/lib/protect.lua")
    package.loaded.buffer = dofile(openOS_address, "/lib/buffer.lua")
    package.loaded.filesystem = dofile(kernel_address, "/kernel/filesystem.lua")

    -- Override the I/O library
    _G.io = dofile(kernel_address, "/kernel/io.lua")

    -- Mount drives
    printk("Initializing file system...")
    local filesystem = require("filesystem")

    -- Mount OpenOS at root
    filesystem.mount(openOS_address, "/")
    -- Mount the kernel so that it's at /boot
    filesystem.mount(kernel_address, "/boot")

    local file = filesystem.open("/kernel.log", "w")
    local _printk = printk
    printk = function(message)
        _printk(message)
        file:write(message .. "\n")
    end
    
    printk("Loading kernel...")

    local protect = require("protect")

    --local buffer = loadKernelAPI("buffer")
    local componentManager = loadKernelAPI("componentManager")
    local component = loadKernelAPI("component")
    local moduleManager = loadKernelAPI("moduleManager")
    local eventManager = loadKernelAPI("eventManager")
    local event = loadKernelAPI("event")
    local keyboard = loadKernelAPI("keyboard")
    local debugger = loadKernelAPI("debugger")
    
    -- Our function APIs may not be 100% compatible with OpenOS' naming scheme
    -- We simply map our function names to OpenOS' names to allow booting with our kernel
    printk("Loading OpenOS compat data...")
    loadKernelAPI("OpenOS_CompatData")

    printk("Protecting kernel APIs...")
    -- Protect kernel structs to prevent applications and OpenOS from overriding stuff
    -- due to the nature of OpenOS we have to protect the kernel in permissive mode
    --buffer = protectKernelAPI(buffer, false)
    filesystem = protectKernelAPI(filesystem, false)
    protect = protectKernelAPI(protect, false)
    componentManager = protectKernelAPI(componentManager, false)
    --component = protectKernelAPI(component, false)
    moduleManager = protectKernelAPI(moduleManager, false)
    eventManager = protectKernelAPI(eventManager, false)
    event = protectKernelAPI(event, false)
    keyboard = protectKernelAPI(keyboard, false)
    debugger = protectKernelAPI(debugger, false)

    printk("(debugger) Hooking APIs...")
    local debuggerOptions = {
        hook_index = true,
        hook_newindex = true,
        hook_call = true,
        proxy_function_calls = true
    }

    --filesystem = debugger.attach(filesystem, "filesystem", debuggerOptions, onDebugger)
    --protect = debugger.attach(protect, "protect", debuggerOptions, onDebugger)
    --componentManager = debugger.attach(componentManager, "componentManager", debuggerOptions, onDebugger)
    --component = debugger.attach(component, "component", debuggerOptions, onDebugger)
    --componentManager.rawComponent = component
    --moduleManager = debugger.attach(moduleManager, "moduleManager", debuggerOptions, onDebugger)
    --eventManager = debugger.attach(eventManager, "eventManager", debuggerOptions, onDebugger)
    --keyboard = debugger.attach(keyboard, "keyboard", debuggerOptions, onDebugger)
    --event = debugger.attach(event, "event", debuggerOptions, onDebugger)

    -- Overwrite loaded packages with new tables so that any new apps can't modify unprotected kernel structs
    -- other kernel code may still modify kernel structs under some circumstances
    --package.loaded.buffer = buffer
    package.loaded.filesystem = filesystem
    package.loaded.protect = protect
    package.loaded.componentManager = componentManager
    package.loaded.component = component
    package.loaded.moduleManager = moduleManager
    package.loaded.eventManager = eventManager
    package.loaded.event = event
    package.loaded.keyboard = keyboard
    package.loaded.debugger = debugger

    printk("Loading kernel modules...")
    for fileName in filesystem.list("/boot/modules") do
        if not filesystem.isDirectory(fileName) then
            local path = filesystem.concat("/boot/modules", fileName)
            printk("Loading kernel module: " .. path)
            local module, message = moduleManager.loadfile(path)
            if not module then
                error("Failed to load kernel module: " .. message)
            end
        end
    end

    printk("Pushing initial events...")
    for component in _component.list() do
        eventManager.push("u", "component_added", component, _component.type(component))
    end

    -- process the unmanaged queue for a while
    repeat
        local event_data = eventManager.pull("u", 0.5)
    until not event_data

    printk("== END OF KERNEL INIT ==")
    printk("Handing back control to the OpenOS bootloader")
end

return function(received_args)
    if _OSVERSION and string.sub(_OSVERSION, 1, string.len(openOS_keyword)) == openOS_keyword then
        output_init()
        openOS_loader(received_args)
    else
        pcall(print, "Platform unsupported!")
        for i=1,5 do
            computer.beep(1000, 0.2)
        end

        computer.shutdown()
    end
end
