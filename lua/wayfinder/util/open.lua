local M = {}

function M.item(item, opener)
  if not item or not item.path or item.path == "" then
    return false
  end

  local target = vim.fn.fnameescape(item.path)
  if opener == "split" then
    vim.cmd.split(target)
  elseif opener == "vsplit" then
    vim.cmd.vsplit(target)
  elseif opener == "tab" then
    vim.cmd.tabedit(target)
  else
    vim.cmd.edit(target)
  end

  pcall(vim.api.nvim_win_set_cursor, 0, {
    item.lnum or 1,
    math.max((item.col or 1) - 1, 0),
  })

  return true
end

return M
