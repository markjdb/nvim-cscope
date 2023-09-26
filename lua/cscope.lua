-- Copyright (c) Mark Johnston <markj@FreeBSD.org>

local posix = require 'posix'

local M = {}

-- lua does not appear to have a standard function for bi-directional popen(),
-- so this function implements it.
local function spawn(cmd, argt)
    local function checked_pipe()
        local r, w = posix.pipe()
        if not r then
            error(("Failed to create pipe: %s"):format(w))
        end
        return r, w
    end
    local inr, inw = checked_pipe()
    local outr, outw = checked_pipe()

    local res, err = posix.fork()
    if not res then
        error(("Failed to fork: %s"):format(err))
    end
    local child = res
    if child == 0 then
        if outw ~= posix.unistd.STDOUT_FILENO then
            res = posix.dup2(outw, posix.unistd.STDOUT_FILENO)
            if not res then
                os.exit(2)
            end
            posix.close(outw)
        end
        posix.close(outr)
        if inr ~= posix.unistd.STDIN_FILENO then
            res = posix.dup2(inr, posix.unistd.STDIN_FILENO)
            if not res then
                os.exit(2)
            end
            posix.close(inr)
        end
        posix.close(inw)

        _, err = posix.execp(cmd, argt)
        io.stderr:write(("Failed to exec %s: %s\n"):format(cmd, err))
        os.exit(1)
    else
        posix.close(inr)
        posix.close(outw)
    end

    local function fdopen(fd, mode)
        -- Work around some kind of bug/incompatibility between luaposix and
        -- luajit.  The following triggers a problem on FreeBSD using
        -- luajit-2.1.0-beta3 and luajit-2.0.5, but not lua-5.*:
        --
        --   local posix = require 'posix'
        --   local f = posix.fdopen(posix.unistd.STDOUT_FILENO, "w")
        --   f:write("hello, world\n")
        --
        --   fdopen.lua:3: calling 'write' on bad self (FILE* expected, got userdata)
        --
        -- In this case the luaposix libraries are compiled against lua 5.1,
        -- which might be the source of the problem, but luajit is supposed to
        -- be binary compatible, right?
        --
        -- So, instead of using posix.fdopen, we create a handle for /dev/null
        -- and recycle it for our purposes.
        res, err = io.open("/dev/null", mode)
        if not res then
            error(("Failed to open /dev/null: %s"):format(err))
        end
        local f = res
        res, err = posix.dup2(fd, posix.stdio.fileno(res))
        if not res then
            error(("Failed to dup2: %s"):format(err))
        end
        return f
    end
    outr = fdopen(outr, "r")
    inw = fdopen(inw, "w")
    return outr, inw, child
end

local CscopeCl = {}

function M.dbopen(dbpath, root)
    dbpath = posix.stdlib.realpath(dbpath)
    local r, w, child = spawn("cscope", {"-dl", "-f", dbpath})
    local res = {
        dbpath = dbpath,
        root = root,
        handle = {
            r = r,
            w = w,
            pid = child,
        }
    }
    return setmetatable(res, { __index = CscopeCl, __gc = CscopeCl.close })
end

function CscopeCl:close()
    local handle = self.handle
    self.handle = nil
    if handle then
        posix.kill(handle.pid, posix.signal.SIGHUP)
        posix.wait(handle.pid)
        handle.r:close()
        handle.w:close()
    end
end

local queries = {
    s = "0", -- symbol definition
    g = "1", -- global definition
    d = "2", -- function callees
    c = "3", -- function callers
    t = "4", -- text string
    e = "6", -- egrep pattern
    f = "7", -- file names
    i = "8", -- includes of this file
    a = "9", -- assignment
}

function CscopeCl:query(query, key)
    local handle = self.handle
    local cmd = queries[query]
    if cmd == nil then
        error(("Invalid query type: %s"):format(query))
    end

    handle.w:write(cmd, key, "\n")
    handle.w:flush()
    local header = handle.r:read("*l")
    if header:match("Unable to search database") then
        return {}
    end
    local count = header:match(">> cscope: (%d+) lines")
    if count == nil then
        error(("Invalid header '%s'"):format(header))
    end
    count = tonumber(count)
    local results = {}
    while count > 0 do
        local match = handle.r:read("l")
        if match == nil then
            error("Unexpected EOF")
        end
        local file, func, lineno, line = match:match("^([^%s]+)%s+([^%s]+)%s+(%d+)%s+(.+)$")
        if file == nil then
            error(("Invalid match: %s"):format(match))
        end
        table.insert(results, {
            key = key,
            file = self.root .. "/" .. file,
            func = func,
            lineno = tonumber(lineno),
            line = line,
        })
        count = count - 1
    end
    return results
end

function CscopeCl:reset()
    self:close()
    local r, w, child = spawn("cscope", {"-dl", "-f", self.dbpath})
    self.handle = {
        r = r,
        w = w,
        pid = child,
    }
end

return M
