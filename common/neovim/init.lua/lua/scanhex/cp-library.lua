local M = {}

-- Helper function that reads a file, expands #includes recursively, and returns the full text.
local function inline_file(relpath, cwd, visited)
  local fullpath = cwd .. "/" .. relpath
  local lines = {}

  -- Attempt to open the file; you might want better error handling here
  local f = io.open(fullpath, "r")
  if not f then
    -- If the file doesn't exist or can't be opened, you might want to
    -- raise an error or just return a comment
    return ("// Could not open file: %s\n"):format(fullpath)
  end

  for line in f:lines() do
    local header = line:match('^%s*#include%s*"([^"]+)"%s*$')
    if header then
      -- If we haven't visited this file yet, expand it recursively
      if not visited[header] then
        visited[header] = true
        table.insert(lines, inline_file(header, cwd, visited))
      end
      -- We skip adding the original #include line,
      -- since we’re inlining it directly.
    else
      local pragma = line:match('^%s*#pragma once%s*$')
      if not pragma then
        line = line:gsub("\r$", "")
        table.insert(lines, line)
      end
    end
  end

  f:close()
  return table.concat(lines, "\n")
end

-- Main function: expands a given filepath (relative to cwd), then inserts the code at cursor
M.dependency_insert = function(filepath, cwd)
  local visited = {}
  local expanded_code = inline_file(filepath, cwd, visited)

  -- If using Neovim, we can paste this directly at the cursor:
  -- Convert expanded code into a list of lines
  local lines = {}
  for line in expanded_code:gmatch("([^\n]*)\n?") do
    table.insert(lines, line)
  end

  -- 3. Insert lines at cursor
  vim.api.nvim_buf_set_lines(0, vim.fn.line('.') - 1, vim.fn.line('.') - 1, false, lines)
  -- Optionally add a newline after
  vim.api.nvim_buf_set_lines(0, vim.fn.line('.') - 1, vim.fn.line('.') - 1, false, { "" })
end

return M
