local telescope = require('telescope')
local actions = require('telescope.actions')
local builtin = require('telescope.builtin')

local function telescope_buffer_dir()
  return vim.fn.expand('%:p:h')
end

local fb_actions = require "telescope".extensions.file_browser.actions
vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
vim.keymap.set('n', '<C-p>', builtin.git_files, {})
vim.keymap.set('n', '<leader>ps', function()
	builtin.grep_string({ search = vim.fn.input("Grep > ") })
end)
vim.keymap.set('n', '<leader>pS', builtin.live_grep, {})
vim.keymap.set('n', '<leader>vh', builtin.help_tags, {})

telescope.setup({
    extensions = {
        rooter = {
            enable = false,
            patterns = { ".git" },
            debug = false
        },
        file_browser = {
            theme = "dropdown",
            -- disables netrw and use telescope-file-browser in its place
            hijack_netrw = true,
            mappings = {
                -- your custom insert mode mappings
                ["i"] = {
                    ["<C-w>"] = function() vim.cmd('normal vbd') end,
                },
                ["n"] = {
                    -- your custom normal mode mappings
                    ["N"] = fb_actions.create,
                    ["h"] = fb_actions.goto_parent_dir,
                    ["s"] = fb_actions.sort_by_date,
                    ["/"] = function()
                        vim.cmd('startinsert')
                    end
                },
            },
        },
    },
    defaults = {
        layout_config = {
            vertical = {
                width = 0.95
            },
            horizontal = {
                width = 0.95
            },
        },
        path_display = {
            "truncate"
        },
        mappings = {
            n = {
                ["q"] = actions.close
            },
        },
    },
})

telescope.load_extension("file_browser")

vim.keymap.set('n', ';f',
function()
    builtin.find_files({
        no_ignore = false,
        hidden = true
    })
end)
vim.keymap.set('n', ';r', function()
    builtin.live_grep()
end)
vim.keymap.set('n', '\\\\', function()
    builtin.buffers()
end)
vim.keymap.set('n', ';t', function()
    builtin.help_tags()
end)
vim.keymap.set('n', ';;', function()
    builtin.resume()
end)
vim.keymap.set('n', ';e', function()
    builtin.diagnostics()
end)
vim.keymap.set('n', ';g', function()
    builtin.git_branches()
end)
vim.keymap.set("n", "sf", function()
    telescope.extensions.file_browser.file_browser({
        path = "%:p:h",
        cwd = telescope_buffer_dir(),
        respect_gitignore = false,
        hidden = true,
        grouped = true,
        previewer = false,
        initial_mode = "normal",
        layout_config = { height = 40 }
    })
end)

require('telescope').load_extension('rooter')
require('telescope').load_extension('cmake4vim')
