return {
    "dpayne/CodeGPT.nvim",
    dependencies = {
        'nvim-lua/plenary.nvim',
        'MunifTanjim/nui.nvim',
    },
    config = function()
        require("codegpt.config")
        vim.g["codegpt_api_provider"] = "anthropic"
        vim.g["codegpt_global_commands_defaults"] = {
            --      model = "gpt-4o",
            model = "claude-3-5-sonnet-20241022",
            max_tokens = 100000,
            temperature = 0.0,
            -- extra_parms = { -- optional list of extra parameters to send to the API
            --     presence_penalty = 1,
            --     frequency_penalty= 1
            -- }
        }
    end
}
