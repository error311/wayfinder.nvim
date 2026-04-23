local M = {}

local links = {
  WayfinderNormal = "NormalFloat",
  WayfinderBorder = "Comment",
  WayfinderTitle = "Comment",
  WayfinderFacet = "Comment",
  WayfinderFacetActive = "Identifier",
  WayfinderCount = "LineNr",
  WayfinderHeader = "Comment",
  WayfinderLabel = "Normal",
  WayfinderLabelSoft = "LineNr",
  WayfinderPath = "Comment",
  WayfinderBadgeLsp = "Function",
  WayfinderBadgeText = "LineNr",
  WayfinderBadgeTest = "String",
  WayfinderBadgeGit = "DiffChange",
  WayfinderPreviewContext = "CursorLine",
  WayfinderPreviewTarget = "Search",
  WayfinderTrail = "DiffAdd",
  WayfinderDim = "Comment",
}

local function hl(name)
  local ok, value = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and value or {}
end

function M.setup()
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = target })
  end

  local normal = hl("Normal")
  local cursorline = hl("CursorLine")
  local visual = hl("Visual")
  local pmenusel = hl("PmenuSel")
  local diffadd = hl("DiffAdd")
  local identifier = hl("Identifier")
  local comment = hl("Comment")
  local selection_bg = pmenusel.bg or cursorline.bg or visual.bg

  vim.api.nvim_set_hl(0, "WayfinderSelection", {
    default = true,
    bg = selection_bg,
  })

  vim.api.nvim_set_hl(0, "WayfinderSelectionAccent", {
    default = true,
    fg = diffadd.fg or identifier.fg,
    bg = selection_bg,
  })

  vim.api.nvim_set_hl(0, "WayfinderSelectionLabel", {
    default = true,
    fg = normal.fg,
    bg = selection_bg,
    bold = true,
  })

  vim.api.nvim_set_hl(0, "WayfinderSelectionPath", {
    default = true,
    fg = comment.fg or normal.fg,
    bg = selection_bg,
  })

  vim.api.nvim_set_hl(0, "WayfinderSelectionMuted", {
    default = true,
    fg = comment.fg or normal.fg,
    bg = selection_bg,
  })
end

return M
