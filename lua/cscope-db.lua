-- Copyright (c) Mark Johnston <markj@FreeBSD.org>

local posix = require 'posix'
local cscope = require 'cscope'

local M = {}

local g_dbdir

local function dbpath(uuid)
    return g_dbdir .. "/" .. uuid .. ".db"
end

local function index_foreach(func)
    local index = io.open(g_dbdir .. "/index", "r")
    if not index then
        error(("Failed to open %s/index for reading"):format(g_dbdir))
    end
    for line in index:lines() do
        local root, uuid = line:match("^([^|]+)|(.+)$")
        func(root, uuid)
    end
    index:close()
end

local function path2db(path)
    local match
    index_foreach(function (root, uuid)
        -- Find the longest root that is a prefix of "path".
        if path:find(root, 1, true) == 1 then
            if not match then
                match = { root = root, uuid = uuid }
            elseif #root > #match.root then
                match.root = root
                match.uuid = uuid
            end
        end
    end)

    return match and dbpath(match.uuid) or nil
end

local function uuidgen()
    local f, err = io.popen("uuidgen")
    if not f then
        error(("Failed to run uuidgen: %s"):format(err))
    end
    local uuid = f:read("*l")
    f:close()
    return uuid
end

function M.init(dbdir)
    if not dbdir then
        dbdir = os.getenv("HOME") .. "/.cscope-mgr"
    end

    local stat = posix.stat(dbdir)
    if not stat then
        local status, err = posix.mkdir(dbdir, 0755)
        if not status then
            error(("Failed to create %s: %s"):format(dbdir, err))
        end
    end

    g_dbdir = dbdir
end

function M.open(path)
    local db = path2db(path)
    if not db then
        error(("No cscope database found for %s"):format(path))
    end
    return cscope.dbopen(db)
end

-- Add a new cscope database for the path.
function M.add(root)
    if not root:match("^/.*") then
        error(("Path must be absolute: %s"):format(root))
    end
    root = posix.realpath(root)
    if path2db(root) then
        error(("cscope database already exists for %s"):format(root))
    end

    local uuid = uuidgen()
    local path = dbpath(uuid)
    local cmd = ("find %s -type f -name \\*.[chSs] -o -name \\*.cpp -o -name \\*.cc | cscope -bqk -i- -f %s")
                :format(root, path)
    local res, err = os.execute(cmd)
    if not res then
        error(("Failed to run cscope: %s"):format(err))
    end

    local index = io.open(g_dbdir .. "/index", "a")
    if not index then
        error(("Failed to open %s/index for writing"):format(g_dbdir))
    end
    res, err = index:write(("%s|%s\n"):format(root, uuid))
    if not res then
        error(("Failed to write to %s/index: %s"):format(g_dbdir, err))
    end
    index:close()
end

-- Return an array of directory paths for which we have cscope databases.
function M.dbs()
    local res = {}
    index_foreach(function (root, _)
        table.insert(res, root)
    end)
    return res
end

return M
