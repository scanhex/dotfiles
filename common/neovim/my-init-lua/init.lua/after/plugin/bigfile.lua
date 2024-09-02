local myvimopts = {
    name = "myvimopts",
    disable = function()
        vim.opt_local.swapfile = false
        vim.opt_local.foldmethod = "manual"
        vim.opt_local.undolevels = 50
        vim.opt_local.undoreload = 0
        vim.opt_local.list = false
    end
}
return {
    "LunarVim/bigfile.nvim",
    lazy = false,
    opts = {
        features = { -- features to disable
            "indent_blankline",
            "illuminate",
            "lsp",
            "treesitter",
            "syntax",
            "matchparen",
            "filetype",
            myvimopts
        },

    }
}
