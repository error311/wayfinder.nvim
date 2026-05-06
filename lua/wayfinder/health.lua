local M = {}

local function target_buffer()
  local current = vim.api.nvim_get_current_buf()
  local current_name = vim.api.nvim_buf_get_name(current)
  if current_name ~= "" and vim.bo[current].buftype == "" then
    return current, current_name
  end

  local alternate = vim.fn.bufnr("#")
  if alternate > 0 and vim.api.nvim_buf_is_valid(alternate) then
    local alternate_name = vim.api.nvim_buf_get_name(alternate)
    if alternate_name ~= "" and vim.bo[alternate].buftype == "" then
      return alternate, alternate_name
    end
  end

  return nil, nil
end

function M.check()
  vim.health.start("wayfinder.nvim")
  local ok_trail_store, trail_store = pcall(require, "wayfinder.trail_store")

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

  local bufnr, path = target_buffer()
  if path and path ~= "" then
    local cwd = vim.uv.cwd()
    local resolved_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
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
      local resolved = scope.resolve(resolved_path, cwd)
      vim.health.info("Resolved scope: " .. resolved.mode .. " → " .. (resolved.root or ""))
      if resolved.project_root then
        vim.health.info("Resolved project root: " .. resolved.project_root)
      end
      if ok_trail_store and resolved.project_root then
        local storage_file = trail_store.project_file(resolved.project_root)
        local saved_count = trail_store.count(resolved.project_root)
        local last_active = trail_store.last_active(resolved.project_root)
        if storage_file then
          vim.health.info("Saved Trail storage file: " .. storage_file)
        end
        if saved_count ~= nil then
          vim.health.info("Saved Trails for current project: " .. tostring(saved_count))
        end
        if last_active then
          vim.health.info("Last active saved Trail: " .. last_active)
        end
      end
    end
  else
    vim.health.info("Open a file to see current-buffer LSP and scope details")
  end

  if ok_trail_store then
    vim.health.info("Saved Trail storage root: " .. trail_store.storage_root())
  end

  local ok_config, config = pcall(require, "wayfinder.config")
  if ok_config and config.values then
    vim.health.info(
      "Current config: performance=" .. tostring(config.values.performance or "balanced")
    )
    vim.health.info(
      "Current config: scope.mode="
        .. tostring(vim.tbl_get(config.values, "scope", "mode") or "project")
    )
  end
end

return M
