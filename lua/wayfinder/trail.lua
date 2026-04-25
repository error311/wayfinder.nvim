local state = require("wayfinder.state")

local M = {}

local function normalize_index(index, count)
  if count == 0 then
    return 1
  end

  return ((index - 1) % count) + 1
end

local function valid_item(item)
  return item and item.path and item.path ~= "" and vim.uv.fs_stat(item.path) ~= nil
end

local function set_cursor(index)
  state.trail_cursor = normalize_index(index, #state.trail)
end

function M.items()
  return vim.deepcopy(state.trail)
end

function M.valid_items()
  local found = {}

  for _, item in ipairs(state.trail) do
    if valid_item(item) then
      found[#found + 1] = vim.deepcopy(item)
    end
  end

  return found
end

function M.has(item_id)
  for _, item in ipairs(state.trail) do
    if item.id == item_id then
      return true
    end
  end
  return false
end

function M.pin(item)
  if not item or M.has(item.id) then
    return false
  end

  local pinned = vim.deepcopy(item)
  pinned.facet = "trail"
  pinned.pinned = true
  pinned.group = "Pinned Trail"
  table.insert(state.trail, pinned)
  set_cursor(#state.trail)
  return true
end

function M.remove(item_id)
  for index, item in ipairs(state.trail) do
    if item.id == item_id then
      table.remove(state.trail, index)
      state.trail_cursor = math.min(state.trail_cursor, math.max(#state.trail, 1))
      return true
    end
  end
  return false
end

function M.clear()
  state.trail = {}
  state.trail_cursor = 1
end

function M.cursor()
  if #state.trail == 0 then
    return nil
  end

  set_cursor(state.trail_cursor)
  return state.trail_cursor
end

function M.current()
  local index = M.cursor()
  return index and state.trail[index] or nil
end

function M.seek(delta, opts)
  local count = #state.trail
  if count == 0 then
    return nil, "empty"
  end

  opts = opts or {}
  local start = normalize_index(opts.start or state.trail_cursor or 1, count)
  local step = delta == nil and 0 or delta

  for offset = 0, count - 1 do
    local index
    if step == 0 then
      index = normalize_index(start + offset, count)
    else
      index = normalize_index(start + (offset * step), count)
    end

    local item = state.trail[index]
    if valid_item(item) then
      state.trail_cursor = index
      return vim.deepcopy(item), index
    end
  end

  return nil, "invalid"
end

return M
