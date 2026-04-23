local state = require("wayfinder.state")

local M = {}

function M.items()
  return vim.deepcopy(state.trail)
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
  return true
end

function M.remove(item_id)
  for index, item in ipairs(state.trail) do
    if item.id == item_id then
      table.remove(state.trail, index)
      return true
    end
  end
  return false
end

function M.clear()
  state.trail = {}
end

return M
