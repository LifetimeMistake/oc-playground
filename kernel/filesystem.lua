local unicode = require("unicode")
local filesystem = {}

-- Use whatever component library is available (probably the unmanaged version)
-- Store this as a field so that the kernel can replace the reference
-- with the managed variant somewhere down the road
filesystem.componentRef = require("component")

local mtab = {
    name = "",
    children = {},
    links = {}
}

local fstab = {}

local function segments(path)
    local parts = {}
    for part in path:gmatch("[^\\/]+") do
        local current, up = part:find("^%.?%.$")
        if current then
            if up == 2 then
                table.remove(parts)
            end
        else
            table.insert(parts, part)
        end
    end

    return parts
end

local function findNode(path, create, resolve_links)
    checkArg(1, path, "string")
    local visited = {}
    local parts = segments(path)
    local ancestry = {}
    local node = mtab
    local index = 1
    while index <= #parts do
        local part = parts[index]
        ancestry[index] = node
        if not node.children[part] then
            local link_path = node.links[part]
            if link_path then
                if not resolve_links and #parts == index then
                    break
                end

                if visited[path] then
                    return nil, string.format("link cycle detected '%s'", path)
                end

                visited[path] = index
                local pst_path = "/" .. table.concat(parts, "/", index + 1)
                local pre_path

                if link_path:match("^[^/]") then
                    pre_path = table.concat(parts, "/", 1, index - 1) .. "/"
                    local link_parts = segments(link_path)
                    local join_parts = segments(pre_path .. link_path)
                    local back = (index - 1 + #link_parts) - #join_parts
                    index = index - back
                    node = ancestry[index]
                else
                    pre_path = ""
                    index = 1
                    node = mtab
                end

                path = pre_path .. link_path .. pst_path
                parts = segments(path)
                part = nil -- skip node movement
            elseif create then
                node.children[part] = {name=part, parent=node, children={}, links={}}
            else
                break
            end
        end
        if part then
            node = node.children[part]
            index = index + 1
        end
    end

    local vnode, vrest = node, #parts >= index and table.concat(parts, "/", index)
    local rest = vrest
    while node and not node.fs do
        rest = rest and filesystem.concat(node.name, rest) or node.name
        node = node.parent
    end
    return node, rest, vnode, vrest
end

filesystem.findNode = findNode

local function deleteVirtual(path)
    local _, _, vnode, vrest = findNode(filesystem.getPath(path), false, true)
    if not vrest then
        local name = filesystem.getFilename(path)
        if vnode and vnode.children[name] or vnode.links[name] then
            vnode.children[name] = nil
            vnode.links[name] = nil

            while vnode and vnode.parent and not vnode.fs and not next(vnode.children) and not next(vnode.links) do
                vnode.parent.children[vnode.name] = nil
                vnode = vnode.parent
            end

            return true
        end
    end

    return false
end

local function deletePhysical(path)
    local node, rest = findNode(path)
    if node.fs and rest then
        return node.fs.remove(rest)
    end

    return false
end

-- public API below

function filesystem.canonical(path)
    local result = table.concat(segments(path), "/")
    if unicode.sub(path, 1, 1) == "/" then
        return "/" .. result
    else
        return result
    end
end

function filesystem.concat(...)
    local set = table.pack(...)
    for index, value in ipairs(set) do
        checkArg(index, value, "string")
    end

    return filesystem.canonical(table.concat(set, "/"))
end

function filesystem.getFilesystem(path)
    local node = findNode(path)
    if node and node.fs then
        local proxy = node.fs
        path = ""

        while node and node.parent do
            path = filesystem.concat(node.name, path)
            node = node.parent
        end

        path = filesystem.canonical(path)
        if path ~= "/" then
            path = "/" .. path
        end

        return proxy, path
    end

    return nil, "no such file system"
end

function filesystem.realPath(path)
    checkArg(1, path, "string")
    local node, rest = findNode(path, false, true)
    if not node then
        return nil, rest
    end

    local parts = {rest or nil}
    repeat
        table.insert(parts, 1, node.name)
        node = node.parent
    until not node

    return table.concat(parts, "/")
end

function filesystem.mount(fs, path)
    checkArg(1, fs, "string", "table")
    if type(fs) == "string" then
        fs = filesystem.componentRef.proxy(fs)
    end

    assert(type(fs) == "table", "bad argument #1 (file system proxy or address expected)")
    checkArg(2, path, "string")

    local realPath
    if not mtab.fs then
        if path == "/" then
            realPath = path
        else
            return nil, "rootfs must be mounted first"
        end
    else
        local message
        realPath, message = filesystem.realPath(path)
        if not realPath then
            return nil, message
        end

        if filesystem.exists(realPath) and not filesystem.isDirectory(realPath) then
            return nil, "mount point is not a directory"
        end
    end

    local fsnode
    if fstab[realPath] then
        return nil, "another filesystem is already mounted here"
    end

    for path,node in pairs(fstab) do
        if node.fs.address == fs.address then
            fsnode = node
            break
        end
    end

    if not fsnode then
        fsnode = select(3, findNode(realPath, true))
        fs.fsnode = fsnode
    else
        local pwd = filesystem.getPath(realPath)
        local parent = select(3, findNode(pwd, true))
        local name = filesystem.getFilename(realPath)

        fsnode = setmetatable({
            name = name,
            parent = parent
        }, { __index=fsnode })

        parent.children[name] = fsnode
    end
    
    fsnode.fs = fs
    fstab[realPath] = fsnode

    return true
end

function filesystem.umount(fsOrPath)
    checkArg(1, fsOrPath, "string", "table")
    local realPath, fs, address

    if type(fsOrPath) == "string" then
        realPath = filesystem.realPath(fsOrPath)
        address = fsOrPath
    else
        fs = fsOrPath
    end
    
    local paths = {}
    for path, node in pairs(fstab) do
        if realPath == path or address == node.fs.address or fs == node.fs then
            table.insert(paths, path)
        end
    end

    for _, path in ipairs(paths) do
        local node = filesystem.fstab[path]
        fstab[path] = nil
        node.fs = nil
        node.parent.children[node.name] = nil
    end

    return #paths > 0
end

function filesystem.mounts()
    local mounts = {}
    for path, node in pairs(fstab) do
        table.insert(mounts, { node.fs, path })
    end

    return function()
        local next = table.remove(mounts)
        if next then
            return table.unpack(next)
        end
    end
end

function filesystem.proxy(addressOrProxy)
    checkArg(1, addressOrProxy, "string", "table")
    if checkType(addressOrProxy, "string") then
        return filesystem.componentRef.proxy(addressOrProxy)
    end

    return addressOrProxy
end

function filesystem.getPath(path)
    local parts = segments(path)
    local result = table.concat(parts, "/", 1, #parts - 1)
    if unicode.sub(path, 1, 1) == "/" and unicode.sub(result, 1, 1) ~= "/" then
        return "/" .. result
    else
        return result
    end
end

function filesystem.getFilename(path)
    checkArg(1, path, "string")
    local parts = segments(path)
    return parts[#parts]
end

function filesystem.exists(path)
    if not filesystem.realPath(filesystem.getPath(path)) then
        return false
    end

    local node, rest, vnode, vrest = findNode(path)
    if not vrest or vnode and vnode.links[vrest] then
        return true
    elseif node and node.fs then
        return node.fs.exists(rest)
    end

    return false
end

function filesystem.isDirectory(path)
    local realPath, reason = filesystem.realPath(path)
    if not realPath then
        return nil, reason
    end

    local node, rest, vnode, vrest = findNode(realPath)
    if vnode and not vnode.fs and not vrest then
        return true
    end

    if node and node.fs then
        return not rest or node.fs.isDirectory(rest)
    end

    return false
end

function filesystem.list(path)
    local node, rest, vnode, vrest = findNode(path, false, true)
    local result = {}
    if node then
        result = node.fs and node.fs.list(rest or "") or {}
        if not vrest and vnode then
            for k,v in pairs(vnode.children) do
                if not v.fs or fstab[filesystem.concat(path, k)] then
                    table.insert(result, k .. "/")
                end
            end

            for k in pairs(vnode.links) do
                table.insert(result, k)
            end
        end
    end

    local set = {}
    for _, name in ipairs(result) do
        set[filesystem.canonical(name)] = name
    end

    return function()
        local k, v = next(set)
        set[k or false] = nil
        return v
    end
end

function filesystem.open(path, mode)
    checkArg(1, path, "string")
    mode = tostring(mode or "r")
    checkArg(2, mode, "string")

    local modes = { r = true, rb = true, w = true, wb = true, a = true, ab = true}
    assert(modes[mode], "bad argument #2 (r[b], w[b] or a[b] expected, got " .. mode .. ")")

    local node, rest = findNode(path, false, true)
    if not node  then
        return nil, rest
    end

    if not node.fs or not rest or (({ r = true, rb = true })[mode] and not node.fs.exists(rest)) then
        return nil, "file not found"
    end

    local handle, reason = node.fs.open(rest, mode)
    if not handle then
        return nil, reason
    end

    return setmetatable({
        fs = node.fs,
        handle = handle
    }, { __index = function(t, k)
        if not t.fs[k] then
            return
        end

        if not t.handle then
            return nil, "file is closed"
        end

        return function(self, ...)
            local h = self.handle
            if k == "close" then
                self.handle = nil
            end

            return self.fs[k](h, ...)
        end
    end})
end

function filesystem.link(target, linkPath)
    checkArg(1, target, "string")
    checkArg(2, linkPath, "string")
    
    if filesystem.exists(linkPath) then
        return nil, "file already exists"
    end

    local linkPath_parent = filesystem.getPath(linkPath)
    if not filesystem.exists(linkPath_parent) then
        return nil, "no such directory"
    end

    local linkPath_real, message = filesystem.realPath(linkPath_parent)
    if not linkPath_real then
        return nil, message
    end

    if not filesystem.isDirectory(linkPath_real) then
        return nil, "not a directory"
    end

    local _, _, vnode, _ = findNode(linkPath_real, true)
    vnode.links[filesystem.name(linkPath)] = target
    return true
end

function filesystem.isLink(path)
    local name = filesystem.getFilename(path)
    local node, rest, vnode, vrest = findNode(filesystem.getPath(path), false, true)

    if not node then
        return nil, rest
    end

    local target = vnode.links[name]
    if not vrest and target ~= nil then
        return true, target
    end

    return false
end

function filesystem.copy(fromPath, toPath)
    local data = false
    local input, output, message
    input, message = filesystem.open(fromPath, "rb")

    if input then
        output, message = filesystem.open(toPath, "wb")
        if output then
            repeat
                data, message = input:read(1024)
                if not data then
                    break
                end

                data, message = output:write(data)
                if not data then
                    data = false
                    message = "failed to write: " .. (message or "<unknown>")
                end
            until not data
            output:close()
        end
        input:close()
    end

    return data == nil, message
end

function filesystem.move(oldPath, newPath)
    if filesystem.isLink(oldPath) then
        local _, _, vnode, _ = findNode(filesystem.path(oldPath))
        local target = vnode.links[filesystem.getFilename(oldPath)]
        local result, message = filesystem.link(target, newPath)

        if not result then
            return nil, message
        end
        
        filesystem.delete(oldPath)
        return true
    else
        local oldNode, oldRest = findNode(oldPath)
        local newNode, newRest = findNode(newPath)
        if oldNode.fs and oldRest and newNode.fs and newRest then
            -- If both paths share the same filesystem then just perform a rename operation
            if oldNode.fs.address == newNode.fs.address then
                return oldNode.fs.rename(oldRest, newRest)
            else -- Physically copy files between filesystems
                local result, message = filesystem.copy(oldPath, newPath)
                if not result then
                    return nil, message
                end

                return filesystem.delete(oldPath)
            end
        end

        return nil, "trying to read from or write to virtual directory"
    end
end

function filesystem.delete(path)
    local success = deleteVirtual(path)
    success = deletePhysical(path) or success
    if success then
        return true
    end

    return nil, "no such file or directory"
end

function filesystem.makeDirectory(path)
    if filesystem.exists(path) then
        return nil, "file or directory with that name already exists"
    end

    local node, rest = findNode(path)
    if node.fs and rest then
        local success, message = node.fs.makeDirectory(rest)
        if not success and not message and node.fs.isReadonly() then
            message = "filesystem is readonly"
        end

        return success, message
    end

    if node.fs then
        return nil, "directory with that name already exists"
    end

    return nil, "cannot create a directory in a virtual directory"
end

function filesystem.getSize(path)
    local node, rest, vnode, vrest = findNode(path, false, true)
    if not node or not vnode.fs and (not vrest or vnode.links[vrest]) then
        return 0
    end

    if node.fs and rest then
        return node.fs.size(rest)
    end

    return 0
end

function filesystem.getLastModified(path)
    local node, rest, vnode, vrest = findNode(path, false, true)
    if not node or not vnode.fs and not vrest then
        return 0
    end

    if node.fs and rest then
        return node.fs.lastModified(rest)
    end

    return 0
end

return filesystem