local paths = require("wayfinder.util.paths")

local M = {}

local function normalize_project_root(project_root)
  return paths.normalize(project_root)
end

local function default_data(project_root)
  return {
    project_root = project_root,
    branch = nil,
    last_active = nil,
    trails = {},
  }
end

local function storage_root(opts)
  opts = opts or {}
  local state_root = paths.normalize(opts.state_root or vim.fn.stdpath("state"))
  return vim.fs.joinpath(state_root, "wayfinder", "trails")
end

local function storage_file(project_root, opts)
  local root = normalize_project_root(project_root)
  if not root or root == "" then
    return nil
  end

  local digest = vim.fn.sha256(root)
  return vim.fs.joinpath(storage_root(opts), digest .. ".json")
end

function M.normalize_item(item)
  if type(item) ~= "table" then
    return {}
  end

  local normalized = {
    id = item.id,
    path = item.path,
    lnum = item.lnum or item.line or 1,
    col = item.col or 1,
    label = item.label,
    secondary = item.secondary,
    detail = item.detail,
    facet = item.facet,
    kind = item.kind,
    source = item.source,
    reason = item.reason,
    badge = item.badge,
  }

  if type(item.preview_range) == "table" then
    normalized.preview_range = {
      start = item.preview_range.start,
      ["end"] = item.preview_range["end"],
    }
  end

  if type(item.git) == "table" then
    normalized.git = {
      hash = item.git.hash,
      relative = item.git.relative,
      repo_root = item.git.repo_root,
    }
  end

  return normalized
end

local function normalize_trail_entry(name, entry)
  if type(entry) ~= "table" then
    return nil
  end

  return {
    name = name,
    items = type(entry.items) == "table" and vim.tbl_map(M.normalize_item, entry.items) or {},
    created_at = entry.created_at,
    updated_at = entry.updated_at,
  }
end

local function normalize_data(project_root, data)
  local normalized = default_data(project_root)

  if type(data) ~= "table" then
    return normalized
  end

  normalized.project_root = normalize_project_root(data.project_root) or project_root
  normalized.branch = data.branch
  normalized.last_active = data.last_active

  if type(data.trails) == "table" then
    for name, entry in pairs(data.trails) do
      if type(name) == "string" and name ~= "" then
        local trail_entry = normalize_trail_entry(name, entry)
        if trail_entry then
          normalized.trails[name] = trail_entry
        end
      end
    end
  end

  return normalized
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "read_failed"
  end

  return table.concat(lines, "\n")
end

function M.project_root(path, cwd)
  return paths.project_root(path, cwd)
end

function M.storage_root(opts)
  return storage_root(opts)
end

function M.project_file(project_root, opts)
  return storage_file(project_root, opts)
end

function M.read_project(project_root, opts)
  local root = normalize_project_root(project_root)
  if not root or root == "" then
    return nil, "missing_project_root"
  end

  local path = storage_file(root, opts)
  if not path or vim.uv.fs_stat(path) == nil then
    return default_data(root)
  end

  local content, read_err = read_file(path)
  if not content then
    return nil, read_err
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    return nil, "invalid_json"
  end

  return normalize_data(root, decoded)
end

local function encode_project_data(data)
  local encoded = vim.deepcopy(data)
  if vim.tbl_isempty(encoded.trails or {}) then
    encoded.trails = vim.empty_dict()
  end
  return encoded
end

function M.write_project(project_root, data, opts)
  local root = normalize_project_root(project_root)
  if not root or root == "" then
    return nil, "missing_project_root"
  end

  local normalized = normalize_data(root, data)
  local path = storage_file(root, opts)
  local dir = vim.fs.dirname(path)
  vim.fn.mkdir(dir, "p")

  local ok, encoded = pcall(vim.json.encode, encode_project_data(normalized))
  if not ok then
    return nil, "encode_failed"
  end

  local write_ok, write_err = pcall(vim.fn.writefile, vim.split(encoded, "\n", { plain = true }), path)
  if not write_ok then
    return nil, write_err
  end

  return normalized
end

function M.list(project_root, opts)
  local data, err = M.read_project(project_root, opts)
  if not data then
    return nil, err
  end

  local names = vim.tbl_keys(data.trails)
  table.sort(names)
  return names
end

function M.get(project_root, name, opts)
  local data, err = M.read_project(project_root, opts)
  if not data then
    return nil, err
  end

  local entry = data.trails[name]
  if not entry then
    return nil, "missing_trail"
  end

  return vim.deepcopy(entry)
end

function M.exists(project_root, name, opts)
  local entry, err = M.get(project_root, name, opts)
  if entry then
    return true
  end
  if err == "missing_trail" then
    return false
  end
  return nil, err
end

function M.set(project_root, trail_data, opts)
  local root = normalize_project_root(project_root)
  if not root or root == "" then
    return nil, "missing_project_root"
  end

  if type(trail_data) ~= "table" or type(trail_data.name) ~= "string" or vim.trim(trail_data.name) == "" then
    return nil, "invalid_trail"
  end

  local data, err = M.read_project(root, opts)
  if not data then
    return nil, err
  end

  local name = vim.trim(trail_data.name)
  local existing = data.trails[name]
  local entry = normalize_trail_entry(name, trail_data) or { name = name, items = {} }
  entry.created_at = trail_data.created_at or (existing and existing.created_at) or os.time()
  entry.updated_at = trail_data.updated_at or os.time()
  data.trails[name] = entry

  return M.write_project(root, data, opts)
end

function M.rename(project_root, old_name, new_name, opts)
  local data, err = M.read_project(project_root, opts)
  if not data then
    return nil, err
  end

  if old_name == new_name then
    return data
  end

  local entry = data.trails[old_name]
  if not entry then
    return nil, "missing_trail"
  end

  if data.trails[new_name] ~= nil then
    return nil, "name_exists"
  end

  data.trails[old_name] = nil
  entry.name = new_name
  data.trails[new_name] = entry

  if data.last_active == old_name then
    data.last_active = new_name
  end

  return M.write_project(project_root, data, opts)
end

function M.delete(project_root, name, opts)
  local data, err = M.read_project(project_root, opts)
  if not data then
    return nil, err
  end

  if data.trails[name] == nil then
    return data, false
  end

  data.trails[name] = nil
  if data.last_active == name then
    data.last_active = nil
  end

  local updated, write_err = M.write_project(project_root, data, opts)
  if not updated then
    return nil, write_err
  end

  return updated, true
end

return M
