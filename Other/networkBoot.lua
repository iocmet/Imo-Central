---@diagnostic disable: undefined-global
-- Network boot usage means that we have internet card so we store some code remotely because of 4096 bytes limit

print(({ ... })[1])
local rootUrl = ({ ... })[1]
local _networkBootRootUrl = rootUrl
local _networkBootMetadata = load('return ' .. httpGet(rootUrl .. '/.networkBoot'), nil, nil, {})()

networkBootFilesystem = {
    getLabel = function ()
        return 'Network Boot Filesystem'
    end,
    setLabel = function (label)
        error('label is read only')
    end,
    isReadOnly = function ()
        return true
    end,
    spaceTotal = function ()
        return 1 * 1024 * 1024
    end,
    spaceUsed = function ()
        return 1 * 1024 * 1024
    end,
    exists = function (path)
        path = path:gsub('^/', ''):gsub('/$', '')
        for directory, files in pairs(_networkBootMetadata.fileList) do
            for _, file in ipairs(files) do
                if path == directory .. '/' .. file or path == file or path == directory then
                    return true
                end
            end
        end
        ocelot.log('File ' .. path .. ' does not exists')
        return false
    end,
    size = function (path)
        --[[ TODO ]]
    end,
    isDirectory = function (path)
        return _networkBootMetadata.fileList[path] ~= nil
    end,
    lastModified = function (path)
        return 0
    end,
    list = function (path)
        local result = {}

        if _networkBootMetadata.fileList[path] then
            for _, file in ipairs(_networkBootMetadata.fileList[path]) do
                table.insert(result, file)
            end
        end

        local dirPrefix = path == '' and '' or path .. '/'
        for subdir in pairs(_networkBootMetadata.fileList) do
            if subdir:sub(1, #dirPrefix) == dirPrefix and subdir ~= path then
                local nextSlash = subdir:find('/', #dirPrefix + 1)
                if not nextSlash then
                    table.insert(result, subdir:sub(#dirPrefix + 1))
                end
            end
        end
    
        return result
    end,
    makeDirectory = function (path)
        return false
    end,
    remove = function (path)
        return false
    end,
    rename = function (from, to)
        return false
    end,
    close = function (handle)
        if networkBootFilesystemHandles[handle] then
            table.remove(networkBootFilesystemHandles, handle)
        end
    end,
    open = function (path, mode)
        mode = mode or 'r'
        if mode ~= 'r' and mode ~= 'rb' then
            return nil, path
        end
        --[[ TODO: Implement length getting ]]
        length = 0
        local handle = { path, mode, 1, length }
        networkBootFilesystemHandles[(math.random() * 2147483647) + 1] = handle
        return handle
    end,
    read = function (handle, count)
        if handle.readAll then
            return nil
        end
        handle.readAll = true
        local data = httpGet(_networkBootRootUrl .. (not handle[1]:find('^/') and ('/' .. handle[1]) or handle[1]))
        return data
    end,
    seek = function (handle, whence, offset)
        local handle = networkBootFilesystemHandles[handle] or error('bad file descriptor')
        if whence == 'cur' then
            handle[3] = handle[3] + offset
        elseif whence == 'set' then
            handle[3] = offset
        elseif whence == 'end' then
            handle[3] = handle[4] + offset
        end
    end,
    write = function (handle, value)
        error('bad file descriptor')
    end
}

local networkBootAddress = 'network-boot-' .. tostring(math.random())
networkBootFilesystem.address = networkBootAddress

local originalComponent = { proxy = component.proxy, invoke = component.invoke, list = component.list }
component.proxy = function (address)
    if address == networkBootAddress then
        return networkBootFilesystem
    else
        return originalComponent.proxy(address)
    end
end
component.invoke = function (address, method, ...)
    if address == networkBootAddress then
        return networkBootFilesystem[method](...)
    else
        return originalComponent.invoke(address, method, ...)
    end
end
component.list = function (filter, exact)
    if exact == nil then
        exact = true
    end
    local originalReturn = originalComponent.list(filter, exact)
    
    if filter == 'filesystem' or (not exact and ('filesystem'):find(filter)) then
        originalReturn[networkBootFilesystem.address] = 'filesystem'
    end
    return originalReturn
end
boot({ filesystem = networkBootAddress, initFile = _networkBootMetadata.initFile })