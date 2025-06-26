return {
    "stevearc/overseer.nvim",
    keys = {
        { "<leader>oo", function() require("overseer").toggle() end, { noremap = true, silent = true } },
        { "<leader>tt", function() require("toggleterm").toggle() end, { noremap = true, silent = true } }
    },
    opts = {
        task_list = {
            direction = "right",
            bindings = {
                ["?"] = "ShowHelp",
                ["g?"] = "ShowHelp",
                ["<CR>"] = "RunAction",
                ["<C-e>"] = "Edit",
                ["o"] = "Open",
                ["<C-v>"] = "OpenVsplit",
                ["<C-s>"] = "OpenSplit",
                ["<C-f>"] = "OpenFloat",
                ["<C-q>"] = "OpenQuickFix",
                ["p"] = "TogglePreview",
                ["<C-l>"] = false,
                ["<C-h>"] = false,
                ["<A-l>"] = "IncreaseDetail",
                ["<A-h>"] = "DecreaseDetail",
                ["L"] = "IncreaseAllDetail",
                ["H"] = "DecreaseAllDetail",
                ["["] = "DecreaseWidth",
                ["]"] = "IncreaseWidth",
                ["{"] = "PrevTask",
                ["}"] = "NextTask",
                ["<C-k>"] = false,
                ["<C-j>"] = false,
                ["<A-k>"] = "ScrollOutputUp",
                ["<A-j>"] = "ScrollOutputDown",
                ["q"] = "Close",
            },
        },
        component_aliases = {
            -- Most tasks are initialized with the default components
            default = {
                { "display_duration", detail_level = 2 },
                "on_output_summarize",
                "on_exit_set_status",
                "on_complete_notify",
                -- "on_complete_dispose", (do not dispose tasks)
            },
            -- Tasks from tasks.json use these components
            default_vscode = {
                "default",
                "on_result_diagnostics",
                "on_result_diagnostics_quickfix",
            },
        },
    }
}
