return {
    "L3MON4D3/LuaSnip",
    config = function()
        local ls = require("luasnip")

        vim.keymap.set({ "i" }, "<C-K>", function() ls.expand() end, { silent = true })
        vim.keymap.set({ "i", "s" }, "<C-L>", function() ls.jump(1) end, { silent = true })
        vim.keymap.set({ "i", "s" }, "<C-J>", function() ls.jump(-1) end, { silent = true })

        local local_config = require("plugins.local.luasnip")
        local_config()
    end,
}
