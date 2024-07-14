return {
    "ThePrimeagen/refactoring.nvim",
    keys = {
        { "<leader>ri", function() require("refactoring").refactor("Inline Variable") end,  mode = "n", { noremap = true, silent = true } },
        { "<leader>re", function() require("refactoring").refactor("Extract Variable") end, mode = "x", { noremap = true, silent = true } },
        { "<leader>rI", function() require("refactoring").refactor("Inline Function") end,  mode = "n", { noremap = true, silent = true } },
        { "<leader>rE", function() require("refactoring").refactor("Extract Function") end, mode = "x", { noremap = true, silent = true } },
    },
}
