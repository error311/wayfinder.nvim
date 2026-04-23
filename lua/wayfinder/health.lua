local M = {}

function M.check()
  vim.health.start("wayfinder.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10+ detected")
  else
    vim.health.error("wayfinder.nvim requires Neovim 0.10+")
  end

  if pcall(require, "wayfinder") then
    vim.health.ok("Plugin modules load")
  else
    vim.health.error("Plugin modules failed to load")
  end

  if vim.lsp then
    vim.health.info("LSP integration enabled when clients are active")
  end
end

return M
