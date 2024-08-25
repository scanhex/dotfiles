return {
    {
        "hrsh7th/cmp-nvim-lsp"
    },
    {
        "folke/neodev.nvim",
        config = {
            lazy = false,
            debug = true,
        }
    },
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "folke/neodev.nvim"
        },
        config = function()
            local capabilities = require('cmp_nvim_lsp').default_capabilities()
            require('lspconfig').clangd.setup {
                capabilities = capabilities,
                cmd = { nixProfilePath .. "/bin/clangd", "--offset-encoding=utf-16", "-j=4" },
            }
            require('lspconfig').pyright.setup {
                capabilities = capabilities
            }
            require('lspconfig').ruff.setup {
                capabilities = capabilities
            }
            require('lspconfig').lua_ls.setup {
                capabilities = capabilities
            }
            require('lspconfig').nil_ls.setup {
                capabilities = capabilities
            }
            require('lspconfig').rust_analyzer.setup {
                capabilities = capabilities
            }
            --require('lspconfig').neocmake.setup {
            --    capabilities = capabilities
            --}

            vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float)
            vim.keymap.set('n', '[d', vim.diagnostic.goto_prev)
            vim.keymap.set('n', ']d', vim.diagnostic.goto_next)
            vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist)

            vim.api.nvim_create_autocmd('LspAttach', {
                group = vim.api.nvim_create_augroup('UserLspConfig', {}),
                callback = function(ev)
                    local opts = { buffer = ev.buf }
                    vim.keymap.set('n', 'gh', "<CMD>ClangdSwitchSourceHeader<CR>", opts)
                    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
                    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
                    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
                    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
                    vim.keymap.set({ 'n', 'i' }, '<C-k>', vim.lsp.buf.signature_help, opts)
                    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
                    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
                    vim.keymap.set('n', '<leader>wl',
                        function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, opts)
                    vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
                    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
                    vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, opts)
                    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
                    vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format { async = true } end, opts)
                end,
            })
        end,
    }
}
