local config = require("wayfinder.config")
local state = require("wayfinder.state")
local facets = require("wayfinder.render.facets")
local list = require("wayfinder.render.list")
local preview = require("wayfinder.render.preview")
local debounce = require("wayfinder.util.debounce")
local paths = require("wayfinder.util.paths")

local M = {}

local core_windows = { "border", "top", "facet", "list", "preview", "bottom" }
local core_buffers = { "top_buf", "facet_buf", "list_buf", "preview_buf", "bottom_buf" }

local function interactive_windows()
  return {
    facet = true,
    list = true,
    preview = true,
  }
end

local preview_debounced = debounce.new(config.values.preview_debounce_ms, function(session)
  if state.current ~= session or not state.ui.preview or not vim.api.nvim_win_is_valid(state.ui.preview) then
    return
  end

  local item = session.visible_items[session.selection_index]
  preview.render(session, state.ui.preview, item)
end)

local function create_buf(name)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "wayfinder"
  return bufnr
end

local function set_lines(bufnr, lines)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

local function add_substring_highlights(bufnr, line, ranges, group)
  local cursor = 1
  for _, needle in ipairs(ranges) do
    local start_col = line:find(needle, cursor, true)
    if start_col then
      vim.api.nvim_buf_add_highlight(bufnr, -1, group, 0, start_col - 1, start_col - 1 + #needle)
      cursor = start_col + #needle
    end
  end
end

local function clear_ui()
  for _, key in ipairs({ "border", "top", "facet", "facet_divider", "list", "list_divider", "preview", "bottom" }) do
    local winid = state.ui[key]
    if winid and vim.api.nvim_win_is_valid(winid) then
      pcall(vim.api.nvim_win_close, winid, true)
    end
    state.ui[key] = nil
  end

  for _, key in ipairs({ "top_buf", "facet_buf", "list_buf", "preview_buf", "bottom_buf", "preview_header" }) do
    state.ui[key] = nil
  end
end

local function ui_valid()
  for _, key in ipairs(core_windows) do
    if not state.ui[key] or not vim.api.nvim_win_is_valid(state.ui[key]) then
      return false
    end
  end

  for _, key in ipairs(core_buffers) do
    if not state.ui[key] or not vim.api.nvim_buf_is_valid(state.ui[key]) then
      return false
    end
  end

  return true
end

local function create_window(bufnr, config_opts, opts)
  opts = opts or {}
  config_opts.focusable = opts.focusable ~= false
  if opts.mouse ~= nil then
    config_opts.mouse = opts.mouse
  end
  if opts.zindex then
    config_opts.zindex = opts.zindex
  end

  local winid = vim.api.nvim_open_win(bufnr, false, config_opts)
  vim.wo[winid].winhighlight = table.concat({
    "Normal:WayfinderNormal",
    "FloatBorder:WayfinderBorder",
    "Title:WayfinderTitle",
  }, ",")
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].wrap = false
  vim.wo[winid].foldenable = false
  vim.wo[winid].spell = false
  vim.wo[winid].list = false
  vim.wo[winid].cursorline = opts.cursorline or false
  vim.wo[winid].scrolloff = opts.scrolloff or 0
  vim.wo[winid].sidescrolloff = opts.sidescrolloff or 0
  vim.wo[winid].cursorlineopt = opts.cursorline and "line" or "both"
  return winid
end

function M.close()
  clear_ui()
end

function M.is_open()
  return ui_valid()
end

function M.open()
  clear_ui()

  local width = math.floor(vim.o.columns * config.values.layout.width)
  local height = math.floor(vim.o.lines * config.values.layout.height)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)
  local facet_width = config.values.layout.facet_width
  local list_width = config.values.layout.list_width
  local header_height = 1
  local footer_height = 1
  local body_height = height - header_height - footer_height - 2
  local preview_width = width - facet_width - list_width - 6

  local border_buf = create_buf("wayfinder://border")
  state.ui.border = create_window(border_buf, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = config.values.layout.border,
    title = config.values.layout.title,
    title_pos = "center",
    style = "minimal",
  }, {
    focusable = false,
    mouse = false,
    zindex = 40,
  })

  local top_buf = create_buf("wayfinder://top")
  state.ui.top_buf = top_buf
  state.ui.top = create_window(top_buf, {
    relative = "editor",
    row = row + 1,
    col = col + 1,
    width = width - 2,
    height = header_height,
    style = "minimal",
  }, {
    focusable = false,
    mouse = false,
    zindex = 60,
  })

  local facet_buf = create_buf("wayfinder://facets")
  state.ui.facet_buf = facet_buf
  state.ui.facet = create_window(facet_buf, {
    relative = "editor",
    row = row + 2,
    col = col + 1,
    width = facet_width,
    height = body_height,
    style = "minimal",
  }, {
    zindex = 60,
    scrolloff = 2,
  })

  local list_buf = create_buf("wayfinder://list")
  state.ui.list_buf = list_buf
  state.ui.list = create_window(list_buf, {
    relative = "editor",
    row = row + 2,
    col = col + facet_width + 2,
    width = list_width,
    height = body_height,
    style = "minimal",
  }, {
    zindex = 60,
    cursorline = false,
    scrolloff = 3,
    sidescrolloff = 1,
  })

  local facet_divider_buf = create_buf("wayfinder://facet-divider")
  set_lines(facet_divider_buf, vim.tbl_map(function()
    return "│"
  end, vim.fn.range(1, body_height)))
  state.ui.facet_divider = create_window(facet_divider_buf, {
    relative = "editor",
    row = row + 2,
    col = col + facet_width + 1,
    width = 1,
    height = body_height,
    style = "minimal",
  }, {
    focusable = false,
    mouse = false,
    zindex = 60,
  })
  vim.wo[state.ui.facet_divider].winhighlight = "Normal:WayfinderDim"

  local preview_buf = create_buf("wayfinder://preview")
  state.ui.preview_buf = preview_buf
  state.ui.preview = create_window(preview_buf, {
    relative = "editor",
    row = row + 2,
    col = col + facet_width + list_width + 3,
    width = preview_width,
    height = body_height,
    style = "minimal",
  }, {
    zindex = 60,
    scrolloff = 3,
    sidescrolloff = 2,
  })

  local list_divider_buf = create_buf("wayfinder://list-divider")
  set_lines(list_divider_buf, vim.tbl_map(function()
    return "│"
  end, vim.fn.range(1, body_height)))
  state.ui.list_divider = create_window(list_divider_buf, {
    relative = "editor",
    row = row + 2,
    col = col + facet_width + list_width + 2,
    width = 1,
    height = body_height,
    style = "minimal",
  }, {
    focusable = false,
    mouse = false,
    zindex = 60,
  })
  vim.wo[state.ui.list_divider].winhighlight = "Normal:WayfinderDim"

  local bottom_buf = create_buf("wayfinder://bottom")
  state.ui.bottom_buf = bottom_buf
  state.ui.bottom = create_window(bottom_buf, {
    relative = "editor",
    row = row + height - 2,
    col = col + 1,
    width = width - 2,
    height = footer_height,
    style = "minimal",
  }, {
    focusable = false,
    mouse = false,
    zindex = 60,
  })

  if state.ui.list and vim.api.nvim_win_is_valid(state.ui.list) then
    vim.api.nvim_set_current_win(state.ui.list)
  end
end

function M.focus_primary()
  if state.ui.list and vim.api.nvim_win_is_valid(state.ui.list) then
    vim.api.nvim_set_current_win(state.ui.list)
  end
end

function M.interactive_window(winid)
  for key in pairs(interactive_windows()) do
    if state.ui[key] == winid then
      return key
    end
  end
  return nil
end

local function add_highlights(bufnr, grouped)
  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  for line, chunks in pairs(grouped or {}) do
    for _, item in ipairs(chunks) do
      local start_col = math.max((item.start_col or 1) - 1, 0)
      local end_col = item.end_col == -1 and -1 or math.max((item.end_col or start_col + 1) - 1, start_col)
      vim.api.nvim_buf_add_highlight(bufnr, -1, item.group, line - 1, start_col, end_col)
    end
  end
end

local function sync_facet_cursor(session)
  if not state.ui.facet or not vim.api.nvim_win_is_valid(state.ui.facet) then
    return
  end

  local rows = facets.rows(session)
  for index, row in ipairs(rows) do
    if row.key == session.facet then
      pcall(vim.api.nvim_win_set_cursor, state.ui.facet, { index, 0 })
      return
    end
  end
end

local function sync_list_cursor(session)
  if not state.ui.list or not vim.api.nvim_win_is_valid(state.ui.list) then
    return
  end

  local selected = session.visible_items[session.selection_index]
  if not selected then
    pcall(vim.api.nvim_win_set_cursor, state.ui.list, { 1, 0 })
    return
  end

  for line = 1, (session.list_line_count or 0) do
    local item = (session.row_actions or {})[line]
    if item and item.id == selected.id then
      pcall(vim.api.nvim_win_set_cursor, state.ui.list, { line, 0 })
      return
    end
  end
end

function M.render(session)
  if not M.is_open() then
    M.open()
  end

  local notice = state.notice_text()
  local mode_label = session.mode == "symbol" and "Symbol" or "File"
  local subject = session.mode == "symbol" and session.subject or vim.fs.basename(session.path)
  local source_file = session.mode == "symbol" and paths.display(session.path, session.cwd) or nil
  local count_label = string.format("%d results", #session.visible_items)
  local loading_label = session.loading and "loading…" or nil
  local filter_label = session.filter ~= "" and ("/" .. session.filter) or nil
  local separator = "  •  "
  local top_segments = {
    { text = " " .. mode_label, group = "WayfinderHeader" },
    { text = separator },
    { text = subject, group = "WayfinderTitle" },
  }

  if source_file and source_file ~= "" and source_file ~= subject then
    table.insert(top_segments, { text = separator })
    table.insert(top_segments, { text = source_file, group = "WayfinderPath" })
  end

  table.insert(top_segments, { text = separator })
  table.insert(top_segments, { text = count_label, group = "WayfinderCount" })

  if loading_label then
    table.insert(top_segments, { text = separator })
    table.insert(top_segments, { text = loading_label, group = "WayfinderDim" })
  end
  if filter_label then
    table.insert(top_segments, { text = separator })
    table.insert(top_segments, { text = filter_label, group = "WayfinderDim" })
  end
  if notice then
    table.insert(top_segments, { text = separator })
    table.insert(top_segments, { text = notice, group = "WayfinderTrail" })
  end

  local top_line = ""
  local top_highlights = {}
  local byte_index = 0
  for _, segment in ipairs(top_segments) do
    local start_col = byte_index
    top_line = top_line .. segment.text
    byte_index = byte_index + #segment.text
    if segment.group then
      table.insert(top_highlights, {
        group = segment.group,
        start_col = start_col,
        end_col = byte_index,
      })
    end
  end

  local top_lines = { top_line }
  set_lines(state.ui.top_buf, top_lines)
  vim.api.nvim_buf_clear_namespace(state.ui.top_buf, -1, 0, -1)
  for _, item in ipairs(top_highlights) do
    vim.api.nvim_buf_add_highlight(state.ui.top_buf, -1, item.group, 0, item.start_col, item.end_col)
  end

  local facet_rows = facets.rows(session)
  set_lines(state.ui.facet_buf, vim.tbl_map(function(row)
    return row.line
  end, facet_rows))
  add_highlights(state.ui.facet_buf, facets.highlights(facet_rows))

  local list_rows, list_hl, actions = list.rows(session)
  set_lines(state.ui.list_buf, list_rows)
  add_highlights(state.ui.list_buf, list_hl)
  session.row_actions = actions
  session.list_line_count = #list_rows
  sync_facet_cursor(session)
  sync_list_cursor(session)

  local bottom_line = " <CR> jump   j/k move   p pin   P trail   x export   / filter   <Tab>/<S-Tab> facets   d details   q close "
  local bottom_lines = { bottom_line }
  set_lines(state.ui.bottom_buf, bottom_lines)
  vim.api.nvim_buf_clear_namespace(state.ui.bottom_buf, -1, 0, -1)
  vim.api.nvim_buf_add_highlight(state.ui.bottom_buf, -1, "WayfinderDim", 0, 1, -1)
  add_substring_highlights(
    state.ui.bottom_buf,
    bottom_line,
    { "<CR>", "j/k", "p", "P", "x", "/", "<Tab>", "<S-Tab>", "d", "q" },
    "WayfinderHeader"
  )

  preview_debounced(session)
end

return M
