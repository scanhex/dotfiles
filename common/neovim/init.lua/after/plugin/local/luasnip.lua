return function()
    local ls = require("luasnip")
    local s = ls.snippet
    local t = ls.text_node
    local i = ls.insert_node

    ls.add_snippets("cpp", {
      s("gtest_header", {
          t({ "#include \"unit_test.h\"", "", ""}),
          t("namespace project::"), i(1), t({" {", ""}),
          t({ "namespace { ", "", ""}),
          i(0),
          t({ "", "}", "" }),
          t({ "}", ""} ),
      }),
    })
end
