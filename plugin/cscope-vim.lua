-- Copyright (c) Mark Johnston <markj@FreeBSD.org>

local cscope = require 'cscope'
local cscopedb = require 'cscope-db'

local g_opendbs = {}

local function imap(l, f)
    local res = {}
    for i, v in ipairs(l) do
        table.insert(res, f(i, v))
    end
    return res
end

local function tconcat(t1, t2)
    for _, v in ipairs(t2) do
        table.insert(t1, v)
    end
end

local function input(matches)
    local function max(l)
        local maxv = nil
        for _, v in ipairs(l) do
            if not maxv or v > maxv then
                maxv = v
            end
        end
        return maxv
    end

    local function width(max)
        local width = 0
        while max > 0 do
            width = width + 1
            max = math.floor(max / 10)
        end
        return width
    end

    local indwidth = width(#matches)
    local indfmt = ("%%%dd"):format(indwidth + 1)
    local linewidth = width(max(vim.tbl_map(function (item) return item.lineno end, matches)))
    local linefmt = ("%%%dd"):format(linewidth + 1)
    local contindent = (" "):rep(indwidth + linewidth + 4)

    local t = imap(matches,
        function (i, v)
            return (indfmt .. " " .. linefmt .. " %s <<%s>>\n%s%s")
                   :format(i, v.lineno, v.file, v.func, contindent, v.line)
        end)
    local str = table.concat(t, "\n") .. "\n"

    local selection
    vim.ui.input({
        prompt = str,
        default = "Type number and <Enter> (q or empty cancels): "
    }, function (input)
        selection = tonumber(input:match("^[^%d]*(%d+)$"))
    end)
    if not selection or selection < 1 or selection > #matches then
        selection = nil
    end
    return selection
end

local function jump(match)
    local item = {{
        tagname = match.key,
        from = { vim.api.nvim_get_current_buf(), vim.fn.line('.'), vim.fn.col('.'), 0 }
    }}
    vim.fn.settagstack(vim.fn.win_getid(), { items = item }, 't')

    local bufnr = vim.fn.bufadd(match.file)
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = true
    vim.api.nvim_set_current_buf(bufnr)
    local line = vim.api.nvim_buf_get_lines(0, match.lineno - 1, match.lineno, false)
    local col = 0
    if #line > 0 then
        -- Try to put the cursor at the beginning of the identifier.  This
        -- doesn't quite work if the identifier appears more than once in the
        -- line, but that's a rare case.
        col = line[1]:find(("[^%%w_]?%s[^%%w_]?"):format(match.key))
        if not col then
            col = 0
        end
        vim.api.nvim_win_set_cursor(0, { match.lineno, col })
    end
    vim.cmd("normal! zz")
end

-- Subcommand table for ":Cscope".  Each function corresponds to a subcommand,
-- e.g., "Cscope find ...".
local nvimcmd = {}

-- Add a new database.  Prompts the user for the root path.
function nvimcmd.add(args)
    if #args ~= 0 then
        vim.api.nvim_err_writeln("usage: Cscope add")
        return
    end

    local path
    vim.ui.input({
        prompt = "Enter the root source path for the new cscope database: ",
        default = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
    }, function (input)
        path = vim.fs.normalize(vim.trim(input))
    end)

    if path then
        cscopedb.add(path)
    else
        vim.api.nvim_err_writeln("Invalid path")
    end
end

-- Close a database.
function nvimcmd.close(args)
    if #args ~= 1 then
        vim.api.nvim_err_writeln("usage: Cscope close <dbnum>")
        return
    end

    local dbnum = tonumber(args[1])
    if not dbnum or dbnum < 1 or dbnum > #g_opendbs then
        vim.api.nvim_err_writeln("Cscope close: invalid dbnum " .. dbnum)
    else
        local db = table.remove(g_opendbs, dbnum)
        db:close()
    end
end

-- Submit a query.
function nvimcmd.find(args)
    if #args ~= 2 then
        vim.api.nvim_err_writeln("usage: Cscope find <query type> <search key>")
        return
    end
    local qtype = args[1]
    local key = args[2]

    local matches = {}
    for _, db in ipairs(g_opendbs) do
        tconcat(matches, db:query(qtype, key))
    end

    if #matches == 0 then
        vim.api.nvim_err_writeln("Cscope find: no matches found for '" .. key .. "'")
    else
        local match = #matches == 1 and 1 or input(matches)
        if match then
            jump(matches[match])
        end
    end
end

local function dbopen(path)
    local db = cscopedb.open(path)
    if db then
        for _, v in ipairs(g_opendbs) do
            if v.dbpath == db.dbpath then
                vim.api.nvim_err_writeln("Cscope open: database already open for " .. db.root)
                return
            end
        end
        table.insert(g_opendbs, db)
    else
        vim.api.nvim_err_writeln("Cscope open: no database found for '" .. file .. "'")
    end
end

-- Open the database corresponding to the specified file.
function nvimcmd.open(args)
    if #args > 1 then
        vim.api.nvim_err_writeln("usage: Cscope open [file]")
        return
    end

    dbopen(args[1] or vim.api.nvim_buf_get_name(0))
end

-- Regenerate the database corresponding to database handle "dbnum", or all
-- open databases if no handle is specified.
function nvimcmd.regen(args)
    if #args > 1 then
        vim.api.nvim_err_writeln("usage: Cscope regen [dbnum]")
        return
    end

    local db = args[1]
    for i, v in ipairs(g_opendbs) do
        if not db or db == i then
            local p = cscopedb.asyncregen(v.root, v.dbpath, vim.loop,
                function (exitcode, signal)
                    if exitcode == 0 then
                        v:reset()
                    else
                        -- Apparently we can't call into the nvim API here,
                        -- and I'm not sure what else we can do to alert the
                        -- user.
                        print("cscope exited with error " .. exitcode)
                    end
                end
            )
        end
    end
end

function nvimcmd.reset(args)
    if #args ~= 0 then
        vim.api.nvim_err_writeln("usage: Cscope reset")
        return
    end

    for _, v in ipairs(g_opendbs) do
        v:reset()
    end
end

function nvimcmd.select(args)
    if #args ~= 0 then
        vim.api.nvim_err_writeln("usage: Cscope select")
        return
    end

    local cwd = vim.fn.getcwd()
    local undercwd = function (p)
        return p:sub(#cwd) == cwd
    end

    local dbs = cscopedb.list()
    table.sort(dbs, function (i, j)
        local ip = undercwd(i)
        local jp = undercwd(j)

        if (ip and jp) or (not ip and not jp) then
            return i < j
        elseif ip then
            return true
        else
            return false
        end
    end)

    local prompt = imap(dbs,
        function (i, v)
            return ("%4d %s"):format(i, v)
        end)
    prompt = table.concat(prompt, "\n") .. "\n"

    local selection
    vim.ui.input({
        prompt = prompt,
        default = "Select a root source path to open: ",
    }, function (input)
        selection = tonumber(input:match("^[^%d]*(%d+)$"))
    end)

    if selection and selection >= 1 and selection <= #dbs then
        dbopen(dbs[selection])
    else
        vim.api.nvim_err_writeln("Invalid selection")
    end
end

-- List open databases.
function nvimcmd.show(args)
    if #args ~= 0 then
        vim.api.nvim_err_writeln("usage: Cscope show")
        return
    end
    local msg = imap(g_opendbs,
        function (i, v)
            return ("%3d %s %s"):format(i, v.dbpath, v.root)
        end)
    print(table.concat(msg, "\n"))
end

local function cscope(a)
    if #a.fargs > 0 then
        func = nvimcmd[a.fargs[1]]
        if func then
            --local args = table.move(a.fargs, 2, #a.fargs, 1)
            table.remove(a.fargs, 1)
            func(a.fargs)
        else
            vim.api.nvim_err_writeln("Cscope: unknown command " .. a.fargs[1])
        end
    end
end

cscopedb.init()
vim.api.nvim_create_user_command("Cscope", cscope, {
    nargs = "*",
    complete = function()
        local keys = vim.tbl_keys(nvimcmd)
        table.sort(keys)
        return keys
    end,
})

-- XXX-MJ does a plugin need to return anything?
