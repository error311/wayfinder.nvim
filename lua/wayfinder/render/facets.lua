local config = require("wayfinder.config")
local text = require("wayfinder.util.text")

local M = {}

local facets = {
  { key = "all", label = "All", icon = function() return config.values.icons.all end },
  { key = "calls", label = "Calls", icon = function() return config.values.icons.calls end },
  { key = "refs", label = "Refs", icon = function() return config.values.icons.refs end },
  { key = "tests", label = "Tests", icon = function() return config.values.icons.tests end },
  { key = "git", label = "Git", icon = function() return config.values.icons.git end },
  { key = "trail", label = "Trail", icon = function() return config.values.icons.trail end },
}

function M.rows(session)
  local rows = {}

  for _, facet in ipairs(facets) do
    local count = session.counts[facet.key]
    local count_text = tostring(count or "…")
    local icon = facet.icon()
    local glue = " · "
    local width = math.max(config.values.layout.facet_width, 12)
    local label_width = math.max(width - vim.fn.strdisplaywidth(count_text) - vim.fn.strdisplaywidth(glue) - 4, 3)
    local label = text.truncate_end(facet.label, label_width)
    local line = string.format(" %s %s%s%s", icon, label, glue, count_text)
    local icon_start = line:find(icon, 1, true) or 2
    local label_start = line:find(label, icon_start + #icon, true) or (icon_start + #icon + 1)
    local glue_start = line:find(glue, label_start + #label, true) or (label_start + #label)
    local count_start = line:find(count_text, 1, true) or (#line - #count_text + 1)

    table.insert(rows, {
      key = facet.key,
      line = line,
      active = session.facet == facet.key,
      count = count,
      label = facet.label,
      icon_start = icon_start,
      icon_end = icon_start + #icon,
      label_start = label_start,
      label_end = label_start + #label,
      glue_start = glue_start,
      glue_end = glue_start + #glue,
      count_start = count_start,
      count_end = count_start + #count_text,
      accent = facet.key == "trail" and (count or 0) > 0,
    })
  end
  return rows
end

function M.highlights(rows)
  local grouped = {}
  for index, row in ipairs(rows) do
    local base_group = row.active and "WayfinderFacetActive" or "WayfinderFacet"
    local icon_group = row.active and "WayfinderFacetActive" or (row.accent and "WayfinderTrail" or "WayfinderHeader")
    local count_group = row.active and "WayfinderFacetActive" or (row.accent and "WayfinderTrail" or "WayfinderCount")

    grouped[index] = {
      { group = base_group, start_col = 1, end_col = -1 },
      { group = icon_group, start_col = row.icon_start, end_col = row.icon_end },
      { group = base_group, start_col = row.label_start, end_col = row.label_end },
      { group = row.active and "WayfinderFacetActive" or "WayfinderDim", start_col = row.glue_start, end_col = row.glue_end },
      { group = count_group, start_col = row.count_start, end_col = row.count_end },
    }
  end
  return grouped
end

function M.facets()
  return facets
end

return M
