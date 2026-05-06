local config = require("wayfinder.config")
local paths = require("wayfinder.util.paths")

local M = {}

local function marker_root(path, cwd, markers, stop)
  local normalized = paths.normalize(path)
  local start = normalized and vim.fn.isdirectory(normalized) == 1 and normalized
    or (normalized and vim.fs.dirname(normalized) or cwd)
  if not start or start == "" then
    return nil
  end

  local marker = vim.fs.find(markers, {
    path = start,
    upward = true,
    stop = stop or vim.uv.os_homedir(),
  })[1]

  if not marker then
    return nil
  end

  return vim.fs.basename(marker) == ".git" and vim.fs.dirname(marker) or vim.fs.dirname(marker)
end

function M.contains(root, path)
  root = paths.normalize(root)
  path = paths.normalize(path)
  if not root or not path then
    return false
  end

  return path == root or vim.startswith(path, root .. "/")
end

function M.filter(items, root)
  if not root then
    return items or {}
  end

  return vim.tbl_filter(function(item)
    return item.path and M.contains(root, item.path)
  end, items or {})
end

function M.resolve(path, cwd)
  cwd = paths.normalize(cwd) or vim.uv.cwd()
  local project_root = paths.project_root(path, cwd)
  local mode = config.values.scope.mode or "project"
  local package_root = nil
  local root = nil

  if mode == "cwd" then
    root = cwd
  elseif mode == "file_dir" then
    root = path and paths.normalize(vim.fs.dirname(path)) or cwd
  elseif mode == "package" then
    package_root = marker_root(
      path,
      cwd,
      config.values.scope.package_markers,
      project_root or vim.uv.os_homedir()
    )
    root = package_root or project_root or cwd
  else
    root = project_root or cwd
  end

  root = paths.normalize(root or cwd)

  return {
    mode = mode,
    root = root,
    cwd = cwd,
    project_root = project_root,
    package_root = package_root,
    label = string.format("%s scope", mode),
  }
end

return M
