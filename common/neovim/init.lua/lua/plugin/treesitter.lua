return {
    {
        "nvim-treesitter/nvim-treesitter-context",
        opts = {
            max_lines = 20,
            min_window_height = 15,
            multiline_threshold = 5
        }
    },
    {
        "nvim-treesitter/nvim-treesitter-textobjects",
        config = function()
            local select = require("nvim-treesitter-textobjects.select")
            local move = require("nvim-treesitter-textobjects.move")

            local select_maps = {
                ["a="] = "@assignment.outer",
                ["i="] = "@assignment.inner",
                ["l="] = "@assignment.lhs",
                ["r="] = "@assignment.rhs",
                ["aa"] = "@parameter.outer",
                ["ia"] = "@parameter.inner",
                ["ai"] = "@conditional.outer",
                ["ii"] = "@conditional.inner",
                ["al"] = "@loop.outer",
                ["il"] = "@loop.inner",
                ["af"] = "@function.outer",
                ["if"] = "@function.inner",
                ["ac"] = "@class.outer",
                ["ic"] = "@class.inner",
            }

            for key, query in pairs(select_maps) do
                vim.keymap.set({ "x", "o" }, key, function()
                    select.select_textobject(query, "textobjects", nil, { lookahead = true })
                end)
            end

            vim.keymap.set({ "n", "x", "o" }, "]m", function() move.goto_next_start("@function.outer", "textobjects") end)
            vim.keymap.set({ "n", "x", "o" }, "]]", function() move.goto_next_start("@class.outer", "textobjects") end)
            vim.keymap.set({ "n", "x", "o" }, "]M", function() move.goto_next_end("@function.outer", "textobjects") end)
            vim.keymap.set({ "n", "x", "o" }, "][", function() move.goto_next_end("@class.outer", "textobjects") end)
            vim.keymap.set({ "n", "x", "o" }, "[m", function() move.goto_previous_start("@function.outer", "textobjects") end)
            vim.keymap.set({ "n", "x", "o" }, "[[", function() move.goto_previous_start("@class.outer", "textobjects") end)
            vim.keymap.set({ "n", "x", "o" }, "[M", function() move.goto_previous_end("@function.outer", "textobjects") end)
            vim.keymap.set({ "n", "x", "o" }, "[]", function() move.goto_previous_end("@class.outer", "textobjects") end)
        end
    },
    {
        "nvim-treesitter/nvim-treesitter",
        dependencies = { "nvim-treesitter/nvim-treesitter-context",
            "nvim-treesitter/nvim-treesitter-textobjects"
        },
        config = function()
            local parser_install_dir = vim.env.NVIM_TREESITTER_PARSERS

            if parser_install_dir ~= nil and parser_install_dir ~= "" then
                parser_install_dir = vim.fn.expand(parser_install_dir)
                if vim.fn.isdirectory(parser_install_dir) == 1 then
                    vim.opt.runtimepath:append(parser_install_dir)
                end
            end

            require("nvim-treesitter-textobjects")
        end
    }
}
