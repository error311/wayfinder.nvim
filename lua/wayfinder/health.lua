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

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("ripgrep found")
  else
    vim.health.warn("ripgrep not found; Text Matches fallback is unavailable")
  end

  if vim.fn.executable("git") == 1 then
    vim.health.ok("git found")
  else
    vim.health.warn("git not found; Git facet is unavailable")
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path ~= "" then
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients > 0 then
      local names = vim.tbl_map(function(client)
        return client.name
      end, clients)
      vim.health.ok("Active LSP clients for current buffer: " .. table.concat(names, ", "))
    else
      vim.health.info("No active LSP clients for current buffer")
    end

    local ok_scope, scope = pcall(require, "wayfinder.util.scope")
    if ok_scope then
      local resolved = scope.resolve(path, vim.uv.cwd())
      vim.health.info("Resolved scope: " .. resolved.mode .. " → " .. (resolved.root or ""))
    end
  else
    vim.health.info("Open a file to see current-buffer LSP and scope details")
  end

  local ok_config, config = pcall(require, "wayfinder.config")
  if ok_config and config.values then
    vim.health.info("Current config: performance=" .. tostring(config.values.performance or "balanced"))
    vim.health.info("Current config: scope.mode=" .. tostring(vim.tbl_get(config.values, "scope", "mode") or "project"))
  end
end

return M
