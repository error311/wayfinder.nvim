local layout = require("wayfinder.layout")
local quickfix = require("wayfinder.util.quickfix")
local state = require("wayfinder.state")
local trail = require("wayfinder.trail")
local open = require("wayfinder.util.open")
local facets = require("wayfinder.render.facets")

local M = {}

local facet_order = { "all", "calls", "refs", "tests", "git", "trail" }

local function current()
  return state.current
end

local function page_step()
  if state.ui.list and vim.api.nvim_win_is_valid(state.ui.list) then
    return math.max(math.floor(vim.api.nvim_win_get_height(state.ui.list) / 2), 1)
  end
  return 5
end

local function set_selection(session, index, opts)
  if not session or #session.visible_items == 0 then
    return
  end

  opts = opts or {}
  local count = #session.visible_items

  if opts.wrap then
    session.selection_index = ((index - 1) % count) + 1
  else
    session.selection_index = math.max(1, math.min(index, count))
  end

  session.selection_id = session.visible_items[session.selection_index].id
end

local function rerender()
  local session = current()
  if session then
    session:refresh_visible()
    layout.render(session)
    layout.focus_primary()
  end
end

local function open_facet(session, facet)
  if not session then
    return
  end

  session.auto_facet_pending = false
  session.facet = facet
  session.selection_id = nil
  session.selection_index = 1
end

local function selection_item()
  local session = current()
  return session and session.visible_items[session.selection_index] or nil
end

local function export_notice(session, message)
  if session and layout.is_open() then
    state.set_notice(message)
    layout.render(session)
    layout.focus_primary()
  else
    vim.notify(message, vim.log.levels.INFO)
  end
end

function M.select_next()
  local session = current()
  if not session or #session.visible_items == 0 then
    return
  end
  set_selection(session, session.selection_index + 1, { wrap = true })
  rerender()
end

function M.select_prev()
  local session = current()
  if not session or #session.visible_items == 0 then
    return
  end
  set_selection(session, session.selection_index - 1, { wrap = true })
  rerender()
end

function M.select_first()
  local session = current()
  if not session or #session.visible_items == 0 then
    return
  end
  set_selection(session, 1)
  rerender()
end

function M.select_last()
  local session = current()
  if not session or #session.visible_items == 0 then
    return
  end
  set_selection(session, #session.visible_items)
  rerender()
end

function M.page_down()
  local session = current()
  if not session or #session.visible_items == 0 then
    return
  end
  set_selection(session, session.selection_index + page_step())
  rerender()
end

function M.page_up()
  local session = current()
  if not session or #session.visible_items == 0 then
    return
  end
  set_selection(session, session.selection_index - page_step())
  rerender()
end

function M.next_facet()
  local session = current()
  if not session then
    return
  end
  for index, key in ipairs(facet_order) do
    if key == session.facet then
      open_facet(session, facet_order[(index % #facet_order) + 1])
      break
    end
  end
  rerender()
end

function M.prev_facet()
  local session = current()
  if not session then
    return
  end
  for index, key in ipairs(facet_order) do
    if key == session.facet then
      open_facet(session, facet_order[((index - 2) % #facet_order) + 1])
      break
    end
  end
  rerender()
end

function M.open_trail()
  local session = current()
  if not session then
    return
  end
  open_facet(session, "trail")
  rerender()
end

function M.focus_list()
  layout.focus_primary()
end

function M.select_item_under_cursor()
  local session = current()
  if not session then
    return
  end

  local winid = vim.api.nvim_get_current_win()
  local area = layout.interactive_window(winid)
  local line = vim.api.nvim_win_get_cursor(winid)[1]

  if area == "facet" then
    local facet = facets.rows(session)[line]
    if facet and facet.key then
      session.facet = facet.key
      session.selection_id = nil
      session.selection_index = 1
      rerender()
    end
    return
  end

  if area == "list" then
    local item = session.row_actions and session.row_actions[line] or nil
    if item then
      for index, visible in ipairs(session.visible_items) do
        if visible.id == item.id then
          set_selection(session, index)
          break
        end
      end
      layout.render(session)
      layout.focus_primary()
    end
    return
  end

  if area == "preview" then
    layout.focus_primary()
  end
end

function M.click_jump()
  M.select_item_under_cursor()
  M.jump()
end

local function push_tagstack(win, tagname)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local from = { bufnr, cursor[1], cursor[2] + 1, 0 }
  local items = { { tagname = tagname ~= "" and tagname or "wayfinder", from = from } }
  pcall(vim.fn.settagstack, win, { items = items }, "t")
end

local function open_item(item, opener)
  local session = current()
  if not session or not item or not item.path then
    return
  end

  local target_win = session.origin_win
  local tagname = (session.symbol and session.symbol.text) or session.subject or ""
  if opener == "edit" or opener == nil then
    push_tagstack(target_win, tagname)
  end

  if session.cancel then
    session:cancel()
  end
  layout.close()
  state.current = nil
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end

  open.item(item, opener)
end

function M.jump()
  open_item(selection_item(), "edit")
end

function M.open_split()
  open_item(selection_item(), "split")
end

function M.open_vsplit()
  open_item(selection_item(), "vsplit")
end

function M.open_tab()
  open_item(selection_item(), "tab")
end

function M.pin()
  local item = selection_item()
  if item and trail.pin(item) then
    local trail_count = #trail.items()
    state.set_notice(string.format("Pinned to Trail • %d item%s", trail_count, trail_count == 1 and "" or "s"), 1800)
    rerender()
  end
end

function M.remove_trail_item()
  local session = current()
  local item = selection_item()
  if session and session.facet == "trail" and item then
    if trail.remove(item.id) then
      session.selection_id = nil
      session.selection_index = math.max(session.selection_index - 1, 1)
      rerender()
    end
  end
end

function M.clear_trail()
  if #trail.items() == 0 then
    export_notice(current(), "Wayfinder: Trail is empty")
    return
  end

  trail.clear()

  local session = current()
  if session then
    session.selection_id = nil
    session.selection_index = 1
    rerender()
    export_notice(session, "Cleared Trail")
  else
    vim.notify("Cleared Trail", vim.log.levels.INFO)
  end
end

function M.export_quickfix()
  local session = current()
  if not session then
    vim.notify("Wayfinder: Wayfinder is not open", vim.log.levels.INFO)
    return
  end

  local found = session.visible_items
  if session.facet == "trail" then
    found = vim.tbl_filter(function(item)
      return item and item.path and item.path ~= "" and vim.uv.fs_stat(item.path) ~= nil
    end, session.visible_items)
  end

  local count = quickfix.export(found, {
    title = "Wayfinder " .. session.facet,
  })
  export_notice(session, string.format("Exported %d item(s) to quickfix", count))
end

function M.export_trail_quickfix()
  local found = trail.valid_items()
  if #found == 0 then
    vim.notify("Wayfinder: Trail is empty", vim.log.levels.INFO)
    return
  end

  local count = quickfix.export(found, {
    title = "Wayfinder Trail",
  })
  export_notice(current(), string.format("Exported %d Trail item(s) to quickfix", count))
end

function M.trail_open()
  local item, status = trail.seek(0)
  if not item then
    if status == "empty" then
      vim.notify("Wayfinder: Trail is empty", vim.log.levels.INFO)
    else
      vim.notify("Wayfinder: Trail has no valid entries", vim.log.levels.INFO)
    end
    return
  end

  open.item(item, "edit")
end

function M.trail_next()
  local item, status = trail.seek(1, { start = (trail.cursor() or 1) + 1 })
  if not item then
    if status == "empty" then
      vim.notify("Wayfinder: Trail is empty", vim.log.levels.INFO)
    else
      vim.notify("Wayfinder: Trail has no valid entries", vim.log.levels.INFO)
    end
    return
  end

  open.item(item, "edit")
end

function M.trail_prev()
  local item, status = trail.seek(-1, { start = (trail.cursor() or 1) - 1 })
  if not item then
    if status == "empty" then
      vim.notify("Wayfinder: Trail is empty", vim.log.levels.INFO)
    else
      vim.notify("Wayfinder: Trail has no valid entries", vim.log.levels.INFO)
    end
    return
  end

  open.item(item, "edit")
end

function M.filter()
  local session = current()
  if not session then
    return
  end

  vim.ui.input({
    prompt = "Wayfinder filter: ",
    default = session.filter,
  }, function(input)
    if input == nil then
      return
    end
    session.filter = input
    session.selection_id = nil
    session.selection_index = 1
    rerender()
  end)
end

function M.clear_filter()
  local session = current()
  if not session or session.filter == "" then
    return
  end

  session.filter = ""
  session.selection_id = nil
  session.selection_index = 1
  rerender()
end

function M.refresh()
  local session = current()
  if session and session.reload then
    session:reload()
  end
end

function M.toggle_details()
  local session = current()
  if session then
    session.show_details = not session.show_details
    layout.render(session)
    layout.focus_primary()
  end
end

function M.close()
  local session = current()
  local target_win = session and session.origin_win or nil
  if session and session.cancel then
    session:cancel()
  end
  layout.close()
  state.current = nil
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    pcall(vim.api.nvim_set_current_win, target_win)
  end
end

return M
