local async = require("wayfinder.util.async")
local paths = require("wayfinder.util.paths")
local state = require("wayfinder.state")
local text = require("wayfinder.util.text")

local M = {}

local function normalize_lines(lines)
  local normalized = {}

  for _, line in ipairs(lines or {}) do
    local text_value = tostring(line or "")
    local parts = vim.split(text_value:gsub("\r", ""), "\n", { plain = true })
    if #parts == 0 then
      normalized[#normalized + 1] = ""
    else
      vim.list_extend(normalized, parts)
    end
  end

  if #normalized == 0 then
    normalized[1] = ""
  end

  return normalized
end

local function ensure_buffer()
  local bufnr = state.ui.preview_buf
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(false, true)
  state.ui.preview_buf = bufnr
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  return bufnr
end

local function set_preview_buffer(bufnr, lines, filetype)
  local normalized = normalize_lines(lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, normalized)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = filetype or ""
  vim.bo[bufnr].syntax = filetype or ""
end

local function clear_highlights(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, state.ui.preview_ns, 0, -1)
end

local function preview_header(session, item)
  if not item then
    return " Preview"
  end

  local path = paths.display(item.path, session.cwd)
  local kind = item.kind and item.kind:gsub("^%l", string.upper) or "Item"
  local source = item.source and item.source:upper() or "ITEM"
  local ordinal = string.format("%d/%d", session.selection_index or 1, math.max(#(session.visible_items or {}), 1))
  local header = string.format(" %s  •  %s  •  %s  •  %s ", path, kind, source, ordinal)
  local width = state.ui.preview and vim.api.nvim_win_is_valid(state.ui.preview)
      and math.max(vim.api.nvim_win_get_width(state.ui.preview) - 1, 1)
    or 80
  return " " .. text.truncate_middle(header, width - 1)
end

local function snippet_window(item)
  local winid = state.ui.preview
  local win_height = winid and vim.api.nvim_win_is_valid(winid)
      and vim.api.nvim_win_get_height(winid)
    or 24
  local before = math.max(math.floor((win_height - 3) * 0.35), 10)
  local after = math.max((win_height - 3) - before + 8, 18)
  local anchor_start = item.preview_range and item.preview_range.start or item.lnum or 1
  local anchor_end = item.preview_range and item.preview_range["end"] or item.lnum or 1
  local start_line = math.max(anchor_start - before, 1)
  local end_line = math.max(anchor_end + after, start_line + before + after)
  return start_line, end_line
end

local function add_line_numbers(bufnr, lines, preview_start)
  if preview_start == nil then
    return
  end

  local width = math.max(#tostring((preview_start or 1) + #lines - 1), 2)
  for index = 1, #lines do
    local lnum = preview_start + index - 1
    vim.api.nvim_buf_set_extmark(bufnr, state.ui.preview_ns, index - 1, 0, {
      virt_text = {
        { string.format("%" .. width .. "d ", lnum), "WayfinderDim" },
      },
      virt_text_pos = "inline",
      priority = 120,
    })
  end
end

local function render_lines(session, item, filetype, lines, preview_start)
  local bufnr = ensure_buffer()
  local winid = state.ui.preview
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local header = preview_header(session, item)
  local preview_width = state.ui.preview and vim.api.nvim_win_is_valid(state.ui.preview)
      and vim.api.nvim_win_get_width(state.ui.preview)
    or 80
  local divider = " " .. string.rep("─", math.max(preview_width - 2, 1))
  local normalized_lines = normalize_lines(lines)

  set_preview_buffer(bufnr, normalized_lines, filetype)
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].cursorline = false
  vim.wo[winid].wrap = false
  vim.wo[winid].winbar = ""

  clear_highlights(bufnr)
  vim.api.nvim_buf_set_extmark(bufnr, state.ui.preview_ns, 0, 0, {
    virt_lines = {
      { { header, "WayfinderDim" } },
      { { divider, "WayfinderDim" } },
    },
    virt_lines_above = true,
    priority = 200,
  })
  add_line_numbers(bufnr, normalized_lines, preview_start)

  if item then
    local line_count = #normalized_lines
    if line_count == 0 then
      return
    end

    local target_line = math.max(item.lnum or 1, 1)
    local start_line = math.max((item.preview_range and item.preview_range.start) or (target_line - 1), 1)
    local end_line = math.max((item.preview_range and item.preview_range["end"] or (target_line + 2)), start_line + 1)
    local preview_offset = math.max(start_line - (preview_start or start_line), 0)
    local target_offset = math.max(target_line - (preview_start or target_line), 0)
    local extmark_start = math.min(preview_offset, line_count - 1)
    local extmark_end = math.min(
      preview_offset + math.max(end_line - start_line, 1),
      line_count
    )
    local target_extmark = math.min(target_offset, line_count - 1)

    vim.api.nvim_buf_set_extmark(bufnr, state.ui.preview_ns, extmark_start, 0, {
      end_line = math.max(extmark_end, extmark_start + 1),
      hl_group = "WayfinderPreviewContext",
      hl_eol = true,
      priority = 60,
    })
    vim.api.nvim_buf_set_extmark(bufnr, state.ui.preview_ns, target_extmark, 0, {
      end_line = math.min(target_extmark + 1, line_count),
      hl_group = "WayfinderPreviewTarget",
      hl_eol = true,
      priority = 90,
    })
    pcall(vim.api.nvim_win_set_cursor, winid, { math.max(target_extmark + 1, 1), 0 })
    pcall(vim.api.nvim_win_call, winid, function()
      vim.cmd.normal({ args = { "zz" }, bang = true })
    end)
    return
  end

  pcall(vim.api.nvim_win_set_cursor, winid, { 1, 0 })
end

local function render_file_preview(session, item)
  local start_line, end_line = snippet_window(item)
  local lines = text.read_lines(item.path, start_line, end_line)
  render_lines(session, item, vim.filetype.match({ filename = item.path }) or "", lines, start_line)
end

local function render_git_preview(session, item)
  async.system({
    "git",
    "show",
    string.format("%s:%s", item.git.hash, item.git.relative),
  }, { cwd = item.git.repo_root }, function(result)
    if state.current ~= session then
      return
    end

    local lines = result.code == 0
      and vim.split(result.stdout or "", "\n", { trimempty = true })
      or {
        "Unable to preview git revision.",
        "",
        vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "git show returned no preview text.",
      }

    render_lines(session, item, vim.filetype.match({ filename = item.path }) or "", lines, 1)
  end)
end

function M.render(session, winid, item)
  ensure_buffer()
  if not item then
    render_lines(session, nil, "", { "  Pick an item to preview" })
    return
  end

  if item.source == "git" and item.git then
    render_lines(session, item, "", { "  Loading git preview…" })
    render_git_preview(session, item)
    return
  end

  render_file_preview(session, item)
end

return M
