if 0 == vim.fn.isdirectory(vim.fn.expand("~/Code/leetcode.nvim")) then
    return {}
end
return {
    --"kawre/leetcode.nvim",
    dir = "~/Code/leetcode.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "nvim-lua/plenary.nvim", -- required by telescope
        "MunifTanjim/nui.nvim",

        -- optional
        "nvim-treesitter/nvim-treesitter",
        "rcarriga/nvim-notify",
        "nvim-tree/nvim-web-devicons",
    },
    opts = {
        debug = true,
        injector = {
            ["cpp"] = {
                before = { "#include <iostream>",
                    "#include <vector>",
                    "#include <algorithm>",
                    "#include <string>",
                    "#include <unordered_map>",
                    "#include <unordered_set>",
                    "#include <map>",
                    "#include <set>",
                    "#include <deque>",
                    "",
                    "using namespace std;",
                    "using nagai = long long",
                    "",
                },
                after = "int main() {}",
            },
        }
    }
}
