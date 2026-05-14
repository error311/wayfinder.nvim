local config = require("wayfinder.config")
local state = require("wayfinder.state")
local layout = require("wayfinder.layout")
local actions = require("wayfinder.actions")
local highlights = require("wayfinder.highlights")
local trail = require("wayfinder.trail")
local symbol_util = require("wayfinder.util.symbol")
local items = require("wayfinder.util.items")
local paths = require("wayfinder.util.paths")
local scope = require("wayfinder.util.scope")
local filter = require("wayfinder.util.filter")
local explore_target = require("wayfinder.util.explore_target")
local sources = {
  lsp = require("wayfinder.sources.lsp"),
  tests = require("wayfinder.sources.tests"),
  git = require("wayfinder.sources.git"),
}

local M = {}

local function remember_facet_selection(session)
  if not session or not session.facet then
    return
  end

  session.facet_memory = session.facet_memory or {}
  local remembered = session.facet_memory[session.facet] or {}
  if session.selection_id then
    remembered.id = session.selection_id
  end
  if session.selection_index then
    remembered.index = session.selection_index
  end
  session.facet_memory[session.facet] = remembered
end

local function cancel_session(session)
  if not session or session.closed then
    return
  end

  session.closed = true
  for _, handle in pairs(session.pending or {}) do
    if handle and handle.cancel then
      pcall(handle.cancel)
    end
  end
  session.pending = {}
end

local function source_key(target, symbol)
  return table.concat({
    target.path or "",
    target.filetype or "",
    symbol and symbol.text or "",
    target.position and target.position.lnum or "",
    target.position and target.position.col or "",
    target.scope and target.scope.mode or "",
    target.scope and target.scope.root or "",
  }, "|")
end

local function attach_clients(from_bufnr, to_bufnr)
  if not from_bufnr or not to_bufnr or from_bufnr == to_bufnr or not vim.lsp then
    return
  end

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = from_bufnr })) do
    pcall(vim.lsp.buf_attach_client, to_bufnr, client.id)
  end
end

local function target_context(opts)
  opts = opts or {}
  if opts.item and opts.item.path and opts.item.path ~= "" then
    local path = vim.fs.normalize(opts.item.path)
    local bufnr = vim.fn.bufnr(path)
    if bufnr < 1 then
      bufnr = vim.fn.bufadd(path)
    end
    if bufnr > 0 then
      vim.fn.bufload(bufnr)
      if vim.bo[bufnr].filetype == "" then
        vim.bo[bufnr].filetype = vim.filetype.match({ filename = path }) or ""
      end
      attach_clients(opts.from_bufnr, bufnr)
    end

    local cwd = opts.cwd or vim.uv.cwd()
    local resolved_scope = scope.resolve(path, cwd)
    return {
      bufnr = bufnr,
      path = path,
      filetype = bufnr > 0 and vim.bo[bufnr].filetype or "",
      cwd = cwd,
      project_root = resolved_scope.project_root,
      scope = resolved_scope,
      explicit_position = true,
      position = opts.item.lnum and opts.item.col and {
        lnum = opts.item.lnum,
        col = opts.item.col,
      } or nil,
    }
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.uv.cwd()
  local normalized_path = path ~= "" and vim.fs.normalize(path) or nil
  local resolved_scope = scope.resolve(normalized_path, cwd)
  local cursor = vim.api.nvim_win_get_cursor(0)

  return {
    bufnr = bufnr,
    path = normalized_path,
    filetype = vim.bo[bufnr].filetype,
    cwd = cwd,
    project_root = resolved_scope.project_root,
    scope = resolved_scope,
    position = normalized_path and {
      lnum = cursor[1],
      col = cursor[2] + 1,
    } or nil,
  }
end

local function history_state(history)
  history = history or {}
  return {
    back = vim.deepcopy(history.back or {}),
    forward = vim.deepcopy(history.forward or {}),
  }
end

local function context_from_session(session)
  if not session or not session.path or session.path == "" then
    return nil
  end

  return {
    item = {
      path = session.path,
      lnum = session.position and session.position.lnum or nil,
      col = session.position and session.position.col or nil,
    },
    label = session.subject,
    cwd = session.cwd,
    from_bufnr = session.bufnr,
  }
end

local function build_counts(session)
  local counts = {
    all = 0,
    calls = 0,
    refs = 0,
    tests = 0,
    git = 0,
    trail = #trail.items(),
  }

  for _, item in ipairs(session.items) do
    counts[item.facet] = (counts[item.facet] or 0) + 1
    counts.all = counts.all + 1
  end

  session.counts = counts
end

local function filtered_items(session)
  local all_items = {}
  for _, item in ipairs(session.items) do
    if session.facet == "all" or session.facet == item.facet then
      item.pinned = trail.has(item.id)
      table.insert(all_items, item)
    end
  end

  if session.facet == "trail" then
    local target_items = {}
    local row_items = {}
    for _, item in ipairs(trail.items()) do
      if item.kind == "target" and item.source == "wayfinder" then
        target_items[#target_items + 1] = item
      else
        row_items[#row_items + 1] = item
      end
    end

    all_items = {}
    vim.list_extend(all_items, target_items)
    vim.list_extend(all_items, row_items)

    for index, item in ipairs(all_items) do
      local group_items = item.kind == "target" and item.source == "wayfinder" and target_items
        or row_items
      local group_index = 1
      for candidate_index, candidate in ipairs(group_items) do
        if candidate.id == item.id then
          group_index = candidate_index
          break
        end
      end
      local previous = group_items[group_index - 1]
      local destination =
        string.format("%s:%d", paths.display(item.path, session.project_root), item.lnum or 1)

      item.icon = group_index == 1 and config.values.icons.trail or "↳"
      item.group = item.kind == "target" and item.source == "wayfinder" and "Explore Targets"
        or "Pinned Rows"
      item.secondary = previous
          and string.format("%02d  %s → %s", group_index, previous.label, destination)
        or string.format("%02d  %s", group_index, destination)
    end
  end

  if session.filter == "" then
    return all_items
  end

  local query = filter.parse(session.filter)
  return vim.tbl_filter(function(item)
    return filter.match(item, query)
  end, all_items)
end

local function refresh_visible(session)
  build_counts(session)

  if session.auto_facet_pending and session.facet == "calls" then
    if session.counts.calls == 0 and session.counts.refs > 1 then
      session.facet = "refs"
      session.selection_id = nil
      session.selection_index = 1
      session.auto_facet_pending = false
    elseif session.counts.calls > 0 then
      session.auto_facet_pending = false
    end
  end

  session.visible_items = filtered_items(session)
  if #session.visible_items == 0 then
    session.selection_index = 1
    return
  end

  if session.selection_id then
    for index, item in ipairs(session.visible_items) do
      if item.id == session.selection_id then
        session.selection_index = index
        remember_facet_selection(session)
        return
      end
    end
  end

  session.selection_index = math.min(session.selection_index or 1, #session.visible_items)
  session.selection_id = session.visible_items[session.selection_index].id
  remember_facet_selection(session)
end

local function aggregate_items(session)
  local merged = {}
  for _, key in ipairs({ "lsp", "tests", "git" }) do
    vim.list_extend(merged, session.results[key].items)
  end
  table.sort(merged, items.score_sort)
  session.items = merged
  session.loading = session.results.lsp.loading
    or session.results.tests.loading
    or session.results.git.loading
  refresh_visible(session)
end

local function keymaps()
  local buffers = {
    state.ui.facet_buf,
    state.ui.list_buf,
    state.ui.preview_buf,
  }

  for _, bufnr in ipairs(buffers) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local map = function(lhs, rhs)
        vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true, silent = true })
      end
      map("j", actions.select_next)
      map("k", actions.select_prev)
      map("gg", actions.select_first)
      map("G", actions.select_last)
      map("<Down>", actions.select_next)
      map("<Up>", actions.select_prev)
      map("<PageDown>", actions.page_down)
      map("<PageUp>", actions.page_up)
      map("<C-d>", actions.page_down)
      map("<C-u>", actions.page_up)
      map("h", actions.prev_facet)
      map("l", actions.next_facet)
      map("<Right>", actions.next_facet)
      map("<Left>", actions.prev_facet)
      map("<Tab>", actions.next_facet)
      map("<S-Tab>", actions.prev_facet)
      map("<CR>", actions.jump)
      map("e", actions.explore_selection)
      map("b", actions.explore_back)
      map("f", actions.explore_forward)
      map("s", actions.open_split)
      map("v", actions.open_vsplit)
      map("t", actions.open_tab)
      map("p", actions.pin)
      map("a", actions.pin_current_target)
      map("A", actions.pin_explore_path)
      map("P", actions.open_trail)
      map("S", actions.trail_menu)
      map("[", actions.prev_saved_trail)
      map("]", actions.next_saved_trail)
      map("x", actions.export_quickfix)
      map("dd", actions.remove_trail_item)
      map("da", actions.clear_trail)
      map("/", actions.filter)
      map("<C-l>", actions.clear_filter)
      map("r", actions.refresh)
      map("D", actions.toggle_details)
      map("?", actions.toggle_hints)
      map("q", actions.close)
      map("<LeftMouse>", actions.select_item_under_cursor)
      map("<2-LeftMouse>", actions.click_jump)
      map("<ScrollWheelDown>", actions.select_next)
      map("<ScrollWheelUp>", actions.select_prev)
    end
  end
end

local function create_session(opts)
  opts = opts or {}
  local target = target_context(opts)
  local symbol = target.explicit_position
      and symbol_util.detect_at(target.path, target.position.lnum, target.position.col)
    or symbol_util.detect()
  local session = {
    id = state.next_id(),
    origin_win = opts.origin_win or vim.api.nvim_get_current_win(),
    mode = symbol and "symbol" or "file",
    subject = symbol and symbol.text or vim.fs.basename(target.path or ""),
    symbol = symbol,
    path = target.path,
    cwd = target.cwd,
    project_root = target.project_root,
    scope = target.scope,
    filetype = target.filetype,
    bufnr = target.bufnr,
    position = target.position,
    history = history_state(opts.history),
    facet = symbol and "calls" or "all",
    auto_facet_pending = symbol ~= nil,
    filter = "",
    selection_index = 1,
    selection_id = nil,
    facet_memory = {},
    show_details = false,
    closed = false,
    loading = true,
    counts = {
      all = 0,
      calls = 0,
      refs = 0,
      tests = 0,
      git = 0,
      trail = #trail.items(),
    },
    items = {},
    visible_items = {},
    results = {
      lsp = { loading = true, items = {} },
      tests = { loading = true, items = {} },
      git = { loading = true, items = {} },
    },
    pending = {},
  }

  function session:refresh_visible()
    refresh_visible(self)
  end

  function session:remember_facet_selection()
    remember_facet_selection(self)
  end

  function session:reload()
    cancel_session(self)
    state.cache = {}
    M.open()
  end

  function session:cancel()
    cancel_session(self)
  end

  return session, target
end

local function update_session(session, source_name, source_items)
  if state.current ~= session or session.closed then
    return
  end

  session.results[source_name] = {
    loading = false,
    items = source_items or {},
  }
  session.pending[source_name] = nil
  aggregate_items(session)
  if state.ui_suspended then
    return
  end
  layout.render(session)
  keymaps()
  if layout.is_open() and not layout.interactive_window(vim.api.nvim_get_current_win()) then
    layout.focus_primary()
  end
end

local function update_session_partial(session, source_name, source_items)
  if state.current ~= session or session.closed then
    return
  end

  session.results[source_name] = {
    loading = true,
    items = source_items or {},
  }
  aggregate_items(session)
  if state.ui_suspended then
    return
  end
  layout.render(session)
  keymaps()
  if layout.is_open() and not layout.interactive_window(vim.api.nvim_get_current_win()) then
    layout.focus_primary()
  end
end

local function load_source(session, target, symbol, source_name)
  if session.closed then
    return
  end

  local key = source_name .. "::" .. source_key(target, symbol)
  local cached = state.cache_get(key, config.values.cache_ttl_ms)
  if cached then
    update_session(session, source_name, cached)
    return
  end

  local handle = sources[source_name].collect({
    bufnr = target.bufnr,
    path = target.path,
    cwd = target.cwd,
    project_root = target.project_root,
    scope = target.scope,
    scope_root = target.scope and target.scope.root or nil,
    filetype = target.filetype,
    position = target.position,
    symbol = symbol,
    is_stale = function()
      return session.closed or state.current ~= session
    end,
    on_partial = function(found)
      update_session_partial(session, source_name, found or {})
    end,
  }, function(found)
    if session.closed or state.current ~= session then
      return
    end
    state.cache_set(key, found or {})
    update_session(session, source_name, found or {})
  end)

  if handle then
    session.pending[source_name] = handle
  end
end

function M.setup(opts)
  config.setup(opts)
  highlights.setup()
end

local function open_session(facet, opts)
  opts = opts or {}
  cancel_session(state.current)
  local session, target = create_session(opts)
  if facet then
    session.facet = facet
    session.auto_facet_pending = false
  end
  state.current = session
  aggregate_items(session)
  if not layout.render(session) then
    session.closed = true
    state.current = nil
    return
  end
  keymaps()
  layout.focus_primary()

  load_source(session, target, session.symbol, "lsp")
  load_source(session, target, session.symbol, "tests")
  load_source(session, target, session.symbol, "git")
end

function M.open()
  open_session()
end

local function selected_explore_target(item, session)
  return explore_target.resolve(item, {
    project_root = session and (session.project_root or session.cwd) or nil,
  })
end

local function show_explore_error(session, target)
  local message = "Wayfinder: " .. (target and target.reason or "No explorable item selected")
  if session and layout.is_open() then
    state.set_notice(message:gsub("^Wayfinder:%s*", ""), 1800)
    layout.render(session)
    keymaps()
    layout.focus_primary()
    return
  end

  local level = target and target.label == "Missing file" and vim.log.levels.WARN
    or vim.log.levels.INFO
  vim.notify(message, level)
end

local function explore_notice(prefix, target)
  state.set_notice(prefix .. " " .. target.label, 1400)
end

local function open_context(context, history, origin_win)
  open_session(nil, {
    item = context.item,
    origin_win = origin_win,
    cwd = context.cwd,
    from_bufnr = context.from_bufnr,
    history = history,
  })
end

function M.explore(item)
  local current = state.current
  if not current then
    vim.notify("Wayfinder: No explorable item selected", vim.log.levels.INFO)
    return
  end

  local target = selected_explore_target(item, current)
  if not target.explorable then
    show_explore_error(current, target)
    return
  end

  local current_context = context_from_session(current)
  local history = history_state(current.history)
  if current_context then
    history.back[#history.back + 1] = current_context
  end
  history.forward = {}

  explore_notice("Exploring", target)
  open_context({
    item = target.item,
    cwd = current.cwd,
    from_bufnr = current.bufnr,
  }, history, current.origin_win)
end

function M.explore_back()
  local current = state.current
  local history = current and history_state(current.history) or nil
  if not current or not history or #history.back == 0 then
    vim.notify("Wayfinder: No previous explore target", vim.log.levels.INFO)
    return
  end

  local target = table.remove(history.back)
  local current_context = context_from_session(current)
  if current_context then
    history.forward[#history.forward + 1] = current_context
  end

  explore_notice("Back to", selected_explore_target(target.item, current))
  open_context(target, history, current.origin_win)
end

function M.explore_forward()
  local current = state.current
  local history = current and history_state(current.history) or nil
  if not current or not history or #history.forward == 0 then
    vim.notify("Wayfinder: No next explore target", vim.log.levels.INFO)
    return
  end

  local target = table.remove(history.forward)
  local current_context = context_from_session(current)
  if current_context then
    history.back[#history.back + 1] = current_context
  end

  explore_notice("Forward to", selected_explore_target(target.item, current))
  open_context(target, history, current.origin_win)
end

function M.export_quickfix()
  actions.export_quickfix()
end

function M.export_trail_quickfix()
  actions.export_trail_quickfix()
end

function M.trail_next()
  actions.trail_next()
end

function M.trail_prev()
  actions.trail_prev()
end

function M.trail_open()
  actions.trail_open()
end

function M.trail_show()
  if state.current and layout.is_open() then
    actions.open_trail()
    return
  end

  open_session("trail")
end

function M.trail_save()
  actions.trail_save()
end

function M.trail_save_as()
  actions.trail_save_as()
end

function M.trail_load()
  actions.trail_load()
end

function M.trail_resume()
  actions.trail_resume()
end

function M.trail_delete()
  actions.trail_delete()
end

function M.trail_rename()
  actions.trail_rename()
end

function M.resume_session_ui()
  local session = state.current
  if not session or session.closed then
    state.ui_suspended = false
    return
  end

  state.ui_suspended = false
  if not layout.render(session) then
    session.closed = true
    state.current = nil
    return
  end
  keymaps()
  layout.focus_primary()
end

return M
