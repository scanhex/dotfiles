-- Minimal gruvbox-dark-hard colorscheme
-- Source: https://github.com/morhetz/gruvbox
vim.cmd("hi clear")
vim.g.colors_name = "gruvbox-hard"

local c = {
  bg0 = "#1d2021", bg1 = "#3c3836", bg2 = "#504945", bg3 = "#665c54",
  fg0 = "#fbf1c7", fg1 = "#ebdbb2", fg2 = "#d5c4a1", fg3 = "#bdae93",
  red = "#fb4934", green = "#b8bb26", yellow = "#fabd2f", blue = "#83a598",
  purple = "#d3869b", aqua = "#8ec07c", orange = "#fe8019", gray = "#928374",
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
hl("Number", { fg = c.purple })
hl("Identifier", { fg = c.blue })
hl("Function", { fg = c.green, bold = true })
hl("Statement", { fg = c.red })
hl("Keyword", { fg = c.red })
hl("PreProc", { fg = c.aqua })
hl("Type", { fg = c.yellow })
hl("Special", { fg = c.orange })
hl("Error", { fg = c.red, bold = true })
hl("Todo", { fg = c.fg0, bg = c.yellow, bold = true })

-- Diagnostics
hl("DiagnosticError", { fg = c.red })
hl("DiagnosticWarn", { fg = c.yellow })
hl("DiagnosticInfo", { fg = c.blue })
hl("DiagnosticHint", { fg = c.aqua })

-- Treesitter
hl("@variable", { fg = c.fg1 })
hl("@function", { fg = c.green, bold = true })
hl("@function.builtin", { fg = c.orange })
hl("@keyword", { fg = c.red })
hl("@string", { fg = c.green })
hl("@type", { fg = c.yellow })
hl("@property", { fg = c.blue })
hl("@comment", { fg = c.gray, italic = true })

-- Git signs
hl("GitSignsAdd", { fg = c.green })
hl("GitSignsChange", { fg = c.aqua })
hl("GitSignsDelete", { fg = c.red })
