-- Example key mappings for the plugin.
--
-- Once a file is open in a buffer, use <leader>cadd to open the corresponding
-- cscope database.  Use <leader>creg to generate it periodically or after making
-- significant edits.
--
-- The <C-\> mappings search for the identifier under the cursor:
-- * <C-\>s finds all references,
-- * <C-\>c finds all calls to the function,
-- * <C-\>d finds all functions called by the function,
-- * <C-\>e finds all functions calling the function,
-- * <C-\>g finds the definition of the identifier,
-- * <C-\>a finds all assignments to the identifier,
-- * <C-\>f finds all files including the file under the cursor.
--
-- If you want to cycle through all matches, use <C-\>q instead of <C-\>, this
-- populates a quickfix list.
--
-- To search for a specific identifier, use :C<letter> <identifier> as an alias
-- for :Cscope find <letter> <identifier>.  :Cq<letter> is an alias for :Cscope
-- quickfix <letter> <identifier>.
--

local function map(lhs, rhs)
    vim.keymap.set('n', lhs, rhs)
end

local function cmd(name, subcmd)
    vim.api.nvim_create_user_command(name, function(a)
        vim.cmd('Cscope ' .. subcmd .. ' ' .. a.args)
        end, { nargs = 1, force = true })
end

map('<leader>cadd', '<cmd>Cscope open<CR>')
map('<leader>cnew', '<cmd>Cscope add<CR>')
map('<leader>creg', '<cmd>Cscope regen<CR>')
map('<leader>csel', '<cmd>Cscope select<CR>')
map('<leader>cr',   '<cmd>Cscope reset<CR>')

local function find_maps(letter, expand)
    expand = expand or '<cword>'
    cmd('C' .. letter, 'find ' .. letter)
    cmd('Cq' .. letter, 'quickfix ' .. letter)
    map('<C-\\>' .. letter,
        function() vim.cmd('Cscope find ' .. letter .. ' ' .. vim.fn.expand(expand)) end)
    map('<C-\\>l' .. letter,
        function() vim.cmd('Cscope find ' .. letter .. ' ' .. vim.fn.expand(expand):lower()) end)
    map('<C-\\>u' .. letter,
        function() vim.cmd('Cscope find ' .. letter .. ' ' .. vim.fn.expand(expand):upper()) end)
    map('<C-\\>q' .. letter,
        function() vim.cmd('Cscope quickfix ' .. letter .. ' ' .. vim.fn.expand(expand)) end)
    map('<C-\\>ql' .. letter,
        function() vim.cmd('Cscope quickfix ' .. letter .. ' ' .. vim.fn.expand(expand):lower()) end)
    map('<C-\\>qu' .. letter,
        function() vim.cmd('Cscope quickfix ' .. letter .. ' ' .. vim.fn.expand(expand):upper()) end)
end

for _, letter in ipairs({ 'a', 'c', 'd', 'e', 'g', 's' }) do
    find_maps(letter)
end
find_maps('f', '<cfile>')

local function bind_ctrl_bracket()
    vim.keymap.set('n', '<C-]>', function()
        vim.cmd('Cscope find g ' .. vim.fn.expand('<cword>'))
    end, { buffer = true })
end

vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'c', 'cpp', 'asm' },
    callback = bind_ctrl_bracket,
})

vim.api.nvim_create_user_command('CscopeBind', bind_ctrl_bracket, {})
