local M = {}

function M.detect()
  local symbol = vim.fn.expand("<cword>")
  if symbol == nil or symbol == "" then
    return nil
  end

  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local start_col = line:sub(1, col):find("[%w_]+$") or col
  local finish_col = line:find("[%W]", col) or (#line + 1)

  return {
    text = symbol,
    range = {
      start_col = start_col,
      end_col = finish_col - 1,
    },
  }
end

return M
