-- Minimal One Light colorscheme
-- Source: https://github.com/atom/one-light-syntax
vim.cmd("hi clear")
vim.g.colors_name = "one-light"

local c = {
  bg0 = "#fafafa", bg1 = "#f0f0f0", bg2 = "#e5e5e6", bg3 = "#a0a1a7",
  fg0 = "#000000", fg1 = "#383a42", fg2 = "#696c77", fg3 = "#a0a1a7",
  red = "#e45649", green = "#50a14f", yellow = "#c18401", blue = "#4078f2",
  purple = "#a626a4", aqua = "#0184bc", orange = "#986801", gray = "#a0a1a7",
  zed_blue_accent = "#5c78e2", zed_blue_function = "#5b79e3",
  zed_blue_type = "#3882b7", zed_hint = "#7274a7",
  zed_operator = "#3882b7", zed_punct = "#242529",
}

local hl = function(g, o) vim.api.nvim_set_hl(0, g, o) end

-- Base
hl("Normal", { fg = c.fg1, bg = "NONE" })
hl("NormalFloat", { fg = c.fg1, bg = c.bg1 })
hl("SignColumn", { bg = "NONE" })
hl("FloatBorder", { fg = c.bg3, bg = c.bg1 })
hl("CursorLine", { bg = c.bg1 })
hl("CursorLineNr", { fg = c.yellow })
hl("LineNr", { fg = c.bg3 })
hl("ColorColumn", { bg = c.bg1 })
hl("VertSplit", { fg = c.bg3 })
hl("WinSeparator", { fg = c.bg3 })
hl("StatusLine", { fg = c.fg1, bg = c.bg2 })
hl("StatusLineNC", { fg = c.bg3, bg = c.bg1 })
hl("Pmenu", { fg = c.fg1, bg = c.bg1 })
hl("PmenuSel", { fg = c.bg1, bg = c.zed_blue_accent, bold = true })
hl("Visual", { bg = c.bg2 })
hl("Search", { fg = c.bg0, bg = c.yellow })
hl("IncSearch", { fg = c.bg0, bg = c.orange })
hl("MatchParen", { fg = c.orange, bold = true })

-- Syntax
hl("Comment", { fg = c.gray, italic = true })
hl("Constant", { fg = c.purple })
hl("String", { fg = c.green })
hl("Number", { fg = c.orange })
hl("Identifier", { fg = c.red })
hl("Function", { fg = c.zed_blue_function, bold = true })
hl("Statement", { fg = c.purple })
hl("Keyword", { fg = c.purple })
hl("PreProc", { fg = c.purple })
hl("Type", { fg = c.zed_blue_type })
hl("Operator", { fg = c.zed_operator })
hl("Special", { fg = c.zed_blue_type })
hl("Error", { fg = c.red, bold = true })
hl("Todo", { fg = c.fg0, bg = c.yellow, bold = true })

-- Diagnostics
hl("DiagnosticError", { fg = c.red })
hl("DiagnosticWarn", { fg = c.yellow })
hl("DiagnosticInfo", { fg = c.zed_blue_accent })
hl("DiagnosticHint", { fg = c.zed_hint })

-- Treesitter
hl("@variable", { fg = c.fg1 })
hl("@function", { fg = c.zed_blue_function, bold = true })
hl("@function.macro", { fg = c.yellow })
hl("@function.builtin", { fg = c.zed_blue_function })
hl("@keyword", { fg = c.purple })
hl("@keyword.import", { fg = c.purple })
hl("@keyword.directive", { fg = c.purple })
hl("@keyword.directive.define", { fg = c.purple })
hl("@keyword.modifier", { fg = c.purple })
hl("@keyword.type", { fg = c.purple })
hl("@operator", { fg = c.zed_operator })
hl("@punctuation", { fg = c.zed_punct })
hl("@punctuation.special", { fg = c.red })
hl("@punctuation.delimiter", { fg = c.zed_punct })
hl("@string", { fg = c.green })
hl("@type", { fg = c.zed_blue_type })
hl("@module", { fg = c.fg1 })
hl("@namespace", { fg = c.fg1 })
hl("@property", { fg = c.red })
hl("@constant.macro", { fg = c.yellow })
hl("@comment", { fg = c.gray, italic = true })

-- LSP semantic token overrides
hl("@lsp.type.macro", { fg = c.yellow })
hl("@lsp.type.namespace", { fg = c.fg1 })
hl("@lsp.type.type", { fg = c.zed_blue_type })
hl("@lsp.type.class", { fg = c.zed_blue_type })
hl("@lsp.type.struct", { fg = c.zed_blue_type })
hl("@lsp.type.interface", { fg = c.zed_blue_type })
hl("@lsp.type.enum", { fg = c.zed_blue_type })
hl("@lsp.type.keyword", { fg = c.purple })
hl("@lsp.type.modifier", { fg = c.purple })
hl("@lsp.type.namespace.cpp", { fg = c.fg1 })
hl("@lsp.type.type.cpp", { fg = c.zed_blue_type })
hl("@lsp.type.class.cpp", { fg = c.zed_blue_type })
hl("@lsp.type.struct.cpp", { fg = c.zed_blue_type })
hl("@lsp.type.interface.cpp", { fg = c.zed_blue_type })
hl("@lsp.type.enum.cpp", { fg = c.zed_blue_type })
hl("@lsp.type.keyword.cpp", { fg = c.purple })
hl("@lsp.type.operator", { fg = c.zed_operator })
hl("@lsp.type.operator.cpp", { fg = c.zed_operator })
hl("@lsp.type.macro.cpp", { fg = c.yellow })
hl("@lsp.typemod.namespace.defaultLibrary.cpp", { fg = c.fg1 })
hl("@lsp.typemod.type.defaultLibrary.cpp", { fg = c.zed_blue_type })

-- Git signs
hl("GitSignsAdd", { fg = c.green })
hl("GitSignsChange", { fg = c.aqua })
hl("GitSignsDelete", { fg = c.red })
