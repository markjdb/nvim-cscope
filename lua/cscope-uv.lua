-- Copyright (c) Mark Johnston <markj@FreeBSD.org>

local M = {}

local CscopeCl = {}

function M.dbopen(dbpath, root)
    local res = {}
    return setmetatable(res, { __index = CscopeCl })
end

function CscopeCl:close()
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
end

return M
