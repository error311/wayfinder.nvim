local M = {}

local function symbol_from_line(line, col)
  if not line or line == "" then
    return nil
  end

  col = math.max(col or 1, 1)
  for start_col, text in line:gmatch("()([%w_]+)") do
    local end_col = start_col + #text - 1
    if start_col <= col and col <= end_col then
      return {
        text = text,
        range = {
          start_col = start_col,
          end_col = end_col,
        },
      }
    end
  end

  return nil
end

function M.detect()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  return symbol_from_line(line, col)
end

function M.detect_at(path, lnum, col)
  if not path or path == "" then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", math.max(lnum or 1, 1))
  if not ok then
    return nil
  end

  return symbol_from_line(lines[lnum or 1], col or 1)
end

return M
