return {
    "t-troebst/perfanno.nvim",
    cmd = { "PerfLuaProfileStart" },
    init = function()
        require("perfanno").setup()
    end,
}
