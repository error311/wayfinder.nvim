local items = require("wayfinder.util.items")
local text = require("wayfinder.util.text")
local config = require("wayfinder.config")

local M = {}

local function find_range(line, needle, init)
  if not line or not needle or needle == "" then
    return nil, nil
  end

  local start_col = line:find(needle, init or 1, true)
  if not start_col then
    return nil, nil
  end

  return start_col, start_col + #needle
end

local function icon_group(item)
  if not item then
    return "WayfinderNormal"
  end
  if item.source == "grep" then
    return "WayfinderDim"
  end
  if item.source == "lsp" then
    return "WayfinderBadgeLsp"
  end
  if item.source == "test" then
    return "WayfinderBadgeTest"
  end
  if item.source == "git" then
    return "WayfinderBadgeGit"
  end
  return "WayfinderDim"
end

local function badge_group(item)
  if not item then
    return "WayfinderNormal"
  end
  if item.source == "lsp" then
    return "WayfinderBadgeLsp"
  end
  if item.source == "grep" then
    return "WayfinderBadgeText"
  end
  if item.source == "test" then
    return "WayfinderBadgeTest"
  end
  if item.source == "git" then
    return "WayfinderBadgeGit"
  end
  return "WayfinderDim"
end

local function label_group(item)
  if not item then
    return "WayfinderLabel"
  end
  if item.source == "grep" then
    return "WayfinderBadgeText"
  end
  return "WayfinderLabel"
end

local function secondary_group(item)
  if not item then
    return "WayfinderPath"
  end
  if item.source == "grep" then
    return "WayfinderDim"
  end
  return "WayfinderPath"
end

local function header_group(group)
  if group == "Definitions" or group == "Callers" or group == "LSP References" then
    return "WayfinderBadgeLsp"
  end
  if group == "Text Matches" then
    return "WayfinderDim"
  end
  if group == "Likely Tests" then
    return "WayfinderDim"
  end
  if group == "Recent Commits" then
    return "WayfinderDim"
  end
  if group == "Pinned Trail" or group == "Explore Targets" then
    return "WayfinderTrail"
  end
  if group == "Pinned Rows" then
    return "WayfinderHeader"
  end
  return "WayfinderHeader"
end

function M.rows(session)
  local rows = {}
  local highlights = {}
  local actions = {}
  local current_group = nil

  if #session.visible_items == 0 then
    rows[1] = session.loading and " Loading…" or " No results"
    highlights[1] = {
      { group = "WayfinderDim", start_col = 1, end_col = -1 },
    }
    return rows, highlights, actions
  end

  local row = 0
  local list_width = config.values.layout.list_width
  for index, item in ipairs(session.visible_items) do
    if item.group and item.group ~= current_group then
      if current_group ~= nil then
        row = row + 1
        rows[row] = ""
      end
      row = row + 1
      rows[row] = " " .. text.truncate_end(item.group, math.max(list_width - 1, 1))
      highlights[row] = {
        { group = header_group(item.group), start_col = 1, end_col = -1 },
      }
      current_group = item.group
    end

    local badge = items.badge_text(item)
    local icon = item.icon or "•"
    local selected = session.selection_index == index
    local prefix = selected and "▎" or " "
    local label_width = math.max(list_width - 8 - vim.fn.strdisplaywidth(badge), 8)
    local label = text.truncate_end(item.label, label_width)
    row = row + 1
    rows[row] = string.format("%s %s %s %s", prefix, icon, label, badge)
    actions[row] = item
    local line = rows[row]
    local icon_start, icon_end = find_range(line, icon)
    local label_start, label_end = find_range(line, label, icon_end)
    local badge_start, badge_end = find_range(line, badge, label_end)
    highlights[row] = {}
    if icon_start then
      table.insert(
        highlights[row],
        { group = icon_group(item), start_col = icon_start, end_col = icon_end }
      )
    end
    if label_start then
      table.insert(
        highlights[row],
        { group = label_group(item), start_col = label_start, end_col = label_end }
      )
    end
    if badge ~= "" and badge_start and badge_end then
      table.insert(
        highlights[row],
        { group = "WayfinderDim", start_col = badge_start, end_col = badge_start + 1 }
      )
      table.insert(
        highlights[row],
        { group = badge_group(item), start_col = badge_start + 1, end_col = badge_end - 1 }
      )
      table.insert(
        highlights[row],
        { group = "WayfinderDim", start_col = badge_end - 1, end_col = badge_end }
      )
    end

    local secondary_parts = {}
    if item.secondary and item.secondary ~= "" then
      secondary_parts[#secondary_parts + 1] = item.secondary
    end
    if session.show_details and item.detail and item.detail ~= "" then
      local already_shown = item.detail == item.secondary
      if not already_shown then
        secondary_parts[#secondary_parts + 1] = item.detail
      end
    end
    local secondary = table.concat(secondary_parts, "  •  ")
    if secondary == "" then
      secondary = item.detail or ""
    end
    secondary = item.source == "grep"
        and text.truncate_middle(secondary, math.max(list_width - 4, 1))
      or text.truncate_end(secondary, math.max(list_width - 4, 1))

    local pinned_icon = item.pinned and config.values.icons.pinned or " "
    row = row + 1
    rows[row] = string.format("%s %s %s", prefix, pinned_icon, secondary)
    actions[row] = item
    highlights[row] = {
      { group = secondary_group(item), start_col = 5, end_col = -1 },
    }
    if item.pinned then
      table.insert(highlights[row], { group = "WayfinderTrail", start_col = 3, end_col = 4 })
    end

    if selected then
      highlights[row - 1] = highlights[row - 1] or {}
      highlights[row] = highlights[row] or {}
      table.insert(
        highlights[row - 1],
        { group = "WayfinderSelection", start_col = 2, end_col = -1 }
      )
      table.insert(highlights[row], { group = "WayfinderSelection", start_col = 2, end_col = -1 })
      table.insert(
        highlights[row - 1],
        { group = "WayfinderSelectionAccent", start_col = 1, end_col = 2 }
      )
      table.insert(
        highlights[row],
        { group = "WayfinderSelectionAccent", start_col = 1, end_col = 2 }
      )
      table.insert(
        highlights[row - 1],
        { group = "WayfinderSelectionMuted", start_col = 3, end_col = -1 }
      )
      if label_start then
        table.insert(
          highlights[row - 1],
          { group = "WayfinderSelectionLabel", start_col = label_start, end_col = label_end }
        )
      end
      table.insert(
        highlights[row],
        { group = "WayfinderSelectionPath", start_col = 5, end_col = -1 }
      )
    end
  end

  return rows, highlights, actions
end

return M
