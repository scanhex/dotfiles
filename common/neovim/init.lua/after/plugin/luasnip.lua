return {
  "L3MON4D3/LuaSnip",
  config = function()
    local ls = require("luasnip")

    vim.keymap.set({ "i" }, "<C-K>", function() ls.expand() end, { silent = true })
    vim.keymap.set({ "i", "s" }, "<C-L>", function() ls.jump(1) end, { silent = true })
    vim.keymap.set({ "i", "s" }, "<C-J>", function() ls.jump(-1) end, { silent = true })

    local s = ls.snippet
    local t = ls.text_node
    local i = ls.insert_node

    ls.add_snippets("cpp", {
      s("compprog", {
        t({
          "#include <algorithm>",
          "#include <iostream>",
          "#include <vector>",
          "#include <map>",
          "#include <set>",
          "#include <array>",
          "#include <cassert>",
          "",
          "using namespace std;",
          "",
          "void solve() {",
          "  " }),
          i(0),
          t({
            "",
            "}",
            "",
            "int main() {",
            "  ios::sync_with_stdio(false);",
            "  cin.tie(0);",
            "  int t = 1;",
            "  cin >> t;",
            "  while (t--) solve();",
            "}",
          }),
      }),
    })

    local local_config = require("plugins.local.luasnip")
    local_config()
  end,
}
