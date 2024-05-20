local function telescope_buffer_dir()
    return vim.fn.expand('%:p:h')
end
return {
    "nvim-telescope/telescope.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "scanhex/telescope-file-browser.nvim",
    },
    config = function()
        local telescope = require('telescope')
        local actions = require('telescope.actions')
        local builtin = require('telescope.builtin')


        local fb_actions = require "telescope".extensions.file_browser.actions

        telescope.setup({
            extensions = {
                rooter = {
                    enable = false,
                    patterns = { ".git" },
                    debug = false
                },
                file_browser = {
                    theme = "dropdown",
                    hijack_netrw = true,
                    mappings = {
                        ["i"] = {
                            ["<C-w>"] = function() vim.cmd('normal vbd') end,
                        },
                        ["n"] = {
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
                    vertical = { width = 0.95 },
                    horizontal = { width = 0.95 },
                },
                path_display = { "truncate" },
                mappings = {
                    n = { ["q"] = actions.close },
                },
            },
        })

        --telescope.load_extension("file_browser")
        --telescope.load_extension('rooter')
        --telescope.load_extension('cmake4vim')
    end,
    keys = {
        { '<leader>pf', function() require("telescope.builtin").find_files() end,                                                                                                                                                                                                          {} },
        { '<C-p>',      function() require("telescope.builtin").git_files() end,                                                                                                                                                                                                           {} },
        { '<leader>ps', function() require("telescope.builtin").grep_string({ search = vim.fn.input("Grep > ") }) end,                                                                                                                                                                     {} },
        { '<leader>pS', function() require("telescope.builtin").live_grep() end,                                                                                                                                                                                                           {} },
        { '<leader>vh', function() require("telescope.builtin").help_tags() end,                                                                                                                                                                                                           {} },
        { ';f',         function() require("telescope.builtin").find_files({ no_ignore = false, hidden = true }) end,                                                                                                                                                                      {} },
        { ';r',         function() require("telescope.builtin").live_grep() end,                                                                                                                                                                                                           {} },
        { '\\\\',       function() require("telescope.builtin").buffers() end,                                                                                                                                                                                                             {} },
        { ';t',         function() require("telescope.builtin").help_tags() end,                                                                                                                                                                                                           {} },
        { ';;',         function() require("telescope.builtin").resume() end,                                                                                                                                                                                                              {} },
        { ';e',         function() require("telescope.builtin").diagnostics() end,                                                                                                                                                                                                         {} },
        { ';g',         function() require("telescope.builtin").git_branches() end,                                                                                                                                                                                                        {} },
        { ';c',         function() require("telescope.builtin").commands() end,                                                                                                                                                                                                            {} },
        { "sf",         function() require("telescope").extensions.file_browser.file_browser({ path = "%:p:h", cwd =
            telescope_buffer_dir(), respect_gitignore = false, hidden = true, grouped = false, previewer = false, initial_mode =
            "normal", layout_config = { height = 40 } }) end,                                                                                                                                                                                                                              {} },
    },
}
