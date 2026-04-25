local layout = require("wayfinder.layout")
local state = require("wayfinder.state")
local trail = require("wayfinder.trail")
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

local function open_item(item, opener)
  local session = current()
  if not session or not item or not item.path then
    return
  end

  local target_win = session.origin_win
  layout.close()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end

  if opener == "split" then
    vim.cmd.split(vim.fn.fnameescape(item.path))
  elseif opener == "vsplit" then
    vim.cmd.vsplit(vim.fn.fnameescape(item.path))
  elseif opener == "tab" then
    vim.cmd.tabedit(vim.fn.fnameescape(item.path))
  else
    vim.cmd.edit(vim.fn.fnameescape(item.path))
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum or 1, math.max((item.col or 1) - 1, 0) })
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
  local session = current()
  local item = selection_item()
  if item and trail.pin(item) then
    local trail_count = #trail.items()
    state.set_notice(trail_count == 1 and "Pinned to Trail" or string.format("Pinned to Trail • %d items", trail_count))
    if session and trail_count >= 2 and session.facet ~= "trail" then
      open_facet(session, "trail")
    end
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
  layout.close()
  state.current = nil
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    pcall(vim.api.nvim_set_current_win, target_win)
  end
end

return M
