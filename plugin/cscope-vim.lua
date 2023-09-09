local cscope = require 'cscope'
local cscopedb = require 'cscope-db'

local g_opendbs = {}

--[[
cscopedb.init()
local csc = cscopedb.open("/usr/home/markj/src/freebsd/sys/vm/vm_page.c")
local matches = csc:query("s", "ticks")

vim.fn.setqflist({}, "r", {
    title = "cscope",
    lines = matches,
})

local function sel(l, f)
    local res = {}
    for _, v in ipairs(l) do
        if f(v) then
            table.insert(res, v)
        end
    end
    return res
end

csc:dbclose()

--[[
vim.ui.select({
    title = "cscope",
    items = sel(matches, function (v) return v.file end),
    callback = function (choice)
        print(choice)
    end,
})
]]
