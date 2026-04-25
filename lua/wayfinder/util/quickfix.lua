local items = require("wayfinder.util.items")

local M = {}

local function entry_text(item)
  local badge = items.badge_text(item)
  local text = item.label or item.detail or item.path or "Wayfinder item"

  if badge ~= "" then
    text = string.format("%s %s", badge, text)
  end

  if item.source == "git" and item.detail and item.detail ~= "" then
    text = string.format("%s -- %s", text, item.detail)
  end

  return text
end

function M.entries(found)
  local entries = {}

  for _, item in ipairs(found or {}) do
    if item and item.path and item.path ~= "" then
      entries[#entries + 1] = {
        filename = item.path,
        lnum = item.lnum or 1,
        col = item.col or 1,
        text = entry_text(item),
      }
    end
  end

  return entries
end

function M.export(found, opts)
  opts = opts or {}
  local entries = M.entries(found)

  vim.fn.setqflist({}, " ", {
    title = opts.title or "Wayfinder",
    items = entries,
  })

  return #entries
end

return M
