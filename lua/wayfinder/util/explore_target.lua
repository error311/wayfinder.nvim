local paths = require("wayfinder.util.paths")
local symbol = require("wayfinder.util.symbol")

local M = {}

local function with_location(label, path, lnum, col, root)
  local location = paths.display(path, root)
  if lnum and col then
    location = string.format("%s:%d:%d", location, lnum, col)
  elseif lnum then
    location = string.format("%s:%d", location, lnum)
  end
  return string.format("%s at %s", label, location)
end

function M.resolve(item, opts)
  opts = opts or {}
  if item and item.kind == "state" then
    return {
      explorable = false,
      label = item.label or "State row",
      top_label = "Explore unavailable",
      detail_label = item.detail or item.reason or "Explore unavailable",
      reason = item.detail or item.reason or "State rows cannot be explored",
    }
  end

  if not item or not item.path or item.path == "" then
    return {
      explorable = false,
      label = "Unavailable",
      top_label = "Explore unavailable",
      detail_label = "Explore unavailable",
      reason = "No explorable item selected",
    }
  end

  if item.source == "git" or item.kind == "commit" then
    return {
      explorable = false,
      label = "Git history",
      top_label = "Explore unavailable",
      detail_label = "Explore unavailable: git rows are file history",
      reason = "Git rows are file history, not code locations",
    }
  end

  local path = vim.fs.normalize(item.path)
  if not path or vim.uv.fs_stat(path) == nil then
    return {
      explorable = false,
      label = "Missing file",
      top_label = "Explore unavailable",
      detail_label = "Explore unavailable: selected file is missing",
      reason = "Selected item is no longer available",
    }
  end

  local lnum = item.lnum
  local col = item.col
  local detected = lnum and col and symbol.detect_at(path, lnum, col) or nil
  local label = detected and detected.text or vim.fs.basename(path)
  local kind = detected and "symbol" or (lnum and "location" or "file")
  local top_label = detected and ("Explore " .. label)
    or (lnum and string.format("Explore %s:%d", label, lnum) or ("Explore " .. label))

  return {
    explorable = true,
    kind = kind,
    symbol = detected,
    label = label,
    top_label = top_label,
    detail_label = with_location("Explore " .. label, path, lnum, col, opts.project_root),
    item = vim.tbl_extend("force", item, { path = path }),
  }
end

return M
