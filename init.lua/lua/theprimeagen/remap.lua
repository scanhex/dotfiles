
vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<leader>h", "<C-W><C-H>")
vim.keymap.set("n", "<leader>l", "<C-W><C-L>")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

vim.keymap.set("n", "<leader>gs", ":G<CR><C-W>L")
vim.keymap.set("n", "<leader>gc", ":G ci -am \"")


-- vim.keymap.set("n", "<leader>vwm", function()
--     require("vim-with-me").StartVimWithMe()
-- end)
-- vim.keymap.set("n", "<leader>svwm", function()
--     require("vim-with-me").StopVimWithMe()
-- end)

-- greatest remap ever
vim.keymap.set("x", "<leader>p", [["_dP]])

-- next greatest remap ever : asbjornHaland
vim.keymap.set({"n", "v"}, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])

vim.keymap.set({"n", "v"}, "<leader>d", [["_d]])

vim.keymap.set("i", "jk", "<Esc>")

vim.keymap.set("n", "]q", ":cnext<CR>")
vim.keymap.set("n", "[q", ":cprev<CR>")

vim.keymap.set("n", "Q", "<nop>")
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)

vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz")
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz")

vim.keymap.set("n", "<leader>r", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>s", ":w<CR>")

function openCMakeListsAndFindFileName()
    local current_file_path = vim.fn.expand('%:p')
    local current_dir = vim.fn.fnamemodify(current_file_path, ':h')
    local file_name_without_extension = vim.fn.fnamemodify(current_file_path, ':t:r')
    local cmake_lists_path = current_dir .. '/CMakeLists.txt'

    if vim.fn.filereadable(cmake_lists_path) == 1 then
        vim.cmd('edit ' .. cmake_lists_path)
        local search_pattern = '(\\W*\\_.\\W*\\zs' .. file_name_without_extension .. '\\ze\\W*$'
        vim.cmd('silent! /' .. search_pattern)
        local last_search_result = vim.fn.getpos("'\"")
        if last_search_result[2] == 0 then
            local search_pattern = file_name_without_extension
            vim.cmd('silent! /' .. search_pattern)
        end
    else
        print('CMakeLists.txt not found in the current directory.')
    end
end
vim.keymap.set('n', '<F4>', ':lua openCMakeListsAndFindFileName()<CR>', { noremap = true, silent = true })

function openCorrespondingTest(current_dir, file_name_without_extension)
    local test_file_path = current_dir .. '/tests/' .. file_name_without_extension .. '_test.cpp'
    vim.cmd('edit ' .. test_file_path)
end
function openCorrespondingSource(current_dir, file_name_without_extension)
    local file_name_without_test_suffix = file_name_without_extension:gsub('_test$', '')
    local source_file_path = current_dir .. '/../' .. file_name_without_test_suffix .. '.cpp'
    vim.cmd('edit ' .. source_file_path)
end
function openCorrespondingTestOrSource()
    local current_file_path = vim.fn.expand('%:p')
    local current_dir = vim.fn.fnamemodify(current_file_path, ':h')
    local file_name_without_extension = vim.fn.fnamemodify(current_file_path, ':t:r')
    if current_file_path:find('_test.cpp$') then
        openCorrespondingSource(current_dir, file_name_without_extension)
    else
        openCorrespondingTest(current_dir, file_name_without_extension)
    end
end
vim.keymap.set("n", "<F5>", ":lua openCorrespondingTestOrSource()<CR>", { noremap = true, silent = true })

vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

vim.keymap.set("n", "<leader>vpp", "<cmd>e ~/.dotfiles/nvim/.config/nvim/lua/theprimeagen/packer.lua<CR>");
vim.keymap.set("n", "<leader>mr", "<cmd>CellularAutomaton make_it_rain<CR>");

vim.keymap.set("n", "<leader><leader>", function()
    vim.cmd("so")
end)

