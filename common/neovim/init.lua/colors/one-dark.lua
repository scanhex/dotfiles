-- Minimal One Dark colorscheme
-- Source: https://github.com/atom/one-dark-syntax
vim.cmd("hi clear")
vim.g.colors_name = "one-dark"

local c = {
  bg0 = "#282c34", bg1 = "#31353f", bg2 = "#393f4a", bg3 = "#4b5263",
  fg0 = "#ffffff", fg1 = "#abb2bf", fg2 = "#9da5b4", fg3 = "#5c6370",
  red = "#e06c75", green = "#98c379", yellow = "#e5c07b", blue = "#61afef",
  purple = "#c678dd", aqua = "#56b6c2", orange = "#d19a66", gray = "#5c6370",
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
hl("PmenuSel", { fg = c.bg1, bg = c.blue, bold = true })
hl("Visual", { bg = c.bg3 })
hl("Search", { fg = c.bg0, bg = c.yellow })
hl("IncSearch", { fg = c.bg0, bg = c.orange })
hl("MatchParen", { fg = c.orange, bold = true })

-- Syntax
hl("Comment", { fg = c.gray, italic = true })
hl("Constant", { fg = c.purple })
hl("String", { fg = c.green })
hl("Number", { fg = c.orange })
hl("Identifier", { fg = c.red })
hl("Function", { fg = c.blue, bold = true })
hl("Statement", { fg = c.purple })
hl("Keyword", { fg = c.purple })
hl("PreProc", { fg = c.aqua })
hl("Type", { fg = c.yellow })
hl("Special", { fg = c.aqua })
hl("Error", { fg = c.red, bold = true })
hl("Todo", { fg = c.fg0, bg = c.yellow, bold = true })

-- Diagnostics
hl("DiagnosticError", { fg = c.red })
hl("DiagnosticWarn", { fg = c.yellow })
hl("DiagnosticInfo", { fg = c.blue })
hl("DiagnosticHint", { fg = c.aqua })

-- Treesitter
hl("@variable", { fg = c.fg1 })
hl("@function", { fg = c.blue, bold = true })
hl("@function.builtin", { fg = c.aqua })
hl("@keyword", { fg = c.purple })
hl("@string", { fg = c.green })
hl("@type", { fg = c.yellow })
hl("@property", { fg = c.red })
hl("@comment", { fg = c.gray, italic = true })

-- Git signs
hl("GitSignsAdd", { fg = c.green })
hl("GitSignsChange", { fg = c.aqua })
hl("GitSignsDelete", { fg = c.red })
