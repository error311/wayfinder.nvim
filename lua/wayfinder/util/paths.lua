local M = {}

function M.normalize(path)
  if not path or path == "" then
    return nil
  end

  return vim.fs.normalize(path)
end

function M.display(path, cwd)
  path = M.normalize(path)
  if not path then
    return "[No Name]"
  end

  if cwd and vim.startswith(path, cwd .. "/") then
    return path:sub(#cwd + 2)
  end

  return vim.fn.fnamemodify(path, ":~")
end

function M.basename(path)
  return path and vim.fs.basename(path) or ""
end

function M.relative_to(base, path)
  base = M.normalize(base)
  path = M.normalize(path)
  if not base or not path then
    return nil
  end

  if vim.startswith(path, base .. "/") then
    return path:sub(#base + 2)
  end

  return path
end

function M.project_root(path, fallback)
  path = M.normalize(path)
  local start = path and vim.fs.dirname(path) or fallback
  if not start or start == "" then
    return fallback
  end

  local marker = vim.fs.find({
    ".git",
    "package.json",
    "Cargo.toml",
    "go.mod",
    "pyproject.toml",
    "setup.py",
  }, {
    path = start,
    upward = true,
    stop = vim.uv.os_homedir(),
  })[1]

  if not marker then
    return fallback or start
  end

  if vim.fs.basename(marker) == ".git" then
    return vim.fs.dirname(marker)
  end

  return vim.fs.dirname(marker)
end

return M
