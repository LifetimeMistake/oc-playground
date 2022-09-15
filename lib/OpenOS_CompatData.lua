-- Provides required compat data for running OpenOS under our kernel

-- Filesystem compat data
local filesystem = require("filesystem")
filesystem.path = filesystem.getPath
filesystem.name = filesystem.getFilename
filesystem.rename = filesystem.move
filesystem.remove = filesystem.delete
filesystem.get = filesystem.getFilesystem
filesystem.size = filesystem.getSize
filesystem.lastModified = filesystem.getLastModified
filesystem.internal = { proxy = filesystem.proxy }

-- Buffer compat data
-- local buffer = require("buffer")
-- buffer.readAll = buffer.readToEnd
-- buffer.formatted_read = buffer.formattedRead
-- buffer.buffered_write = buffer.bufferedWrite
-- buffer.size = buffer.getSize