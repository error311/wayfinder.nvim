local layout = require("wayfinder.layout")
local quickfix = require("wayfinder.util.quickfix")
local state = require("wayfinder.state")
local trail = require("wayfinder.trail")
local trail_persistence = require("wayfinder.trail_persistence")
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
  if session.remember_facet_selection then
    session:remember_facet_selection()
  end
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

  if session.remember_facet_selection then
    session:remember_facet_selection()
  end

  session.auto_facet_pending = false
  session.facet = facet
  local remembered = session.facet_memory and session.facet_memory[facet] or nil
  session.selection_id = remembered and remembered.id or nil
  session.selection_index = remembered and remembered.index or 1
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

local function normalize_name(name)
  if type(name) ~= "string" then
    return nil
  end

  local trimmed = vim.trim(name)
  if trimmed == "" then
    return nil
  end

  return trimmed
end

local function persistence_notice(message)
  export_notice(current(), message)
end

local function persistence_error_message(err, name)
  if err == "empty" then
    return "Wayfinder: Trail is empty"
  end
  if err == "missing_project_root" then
    return "Wayfinder: Unable to resolve project root for Trail storage"
  end
  if err == "missing_name" then
    return "Wayfinder: Trail name is required"
  end
  if err == "name_exists" then
    return string.format("Wayfinder: Trail already exists: %s", name or "")
  end
  if err == "missing_trail" then
    return string.format("Wayfinder: Saved Trail not found: %s", name or "")
  end
  if err == "invalid_json" then
    return "Wayfinder: Saved Trail storage is invalid"
  end
  if err == "read_failed" then
    return "Wayfinder: Unable to read saved Trail storage"
  end
  if err == "encode_failed" then
    return "Wayfinder: Unable to encode Trail storage"
  end
  if err == "invalid_trail" then
    return "Wayfinder: Saved Trail data is invalid"
  end
  if err == "no_saved_trails" then
    return "Wayfinder: No saved Trails"
  end
  return "Wayfinder: Trail persistence failed"
end

local function persistence_warn(err, name)
  vim.notify(persistence_error_message(err, name), vim.log.levels.WARN)
end

local function with_suspended_ui(start)
  local session = current()
  local suspended = session and layout.is_open()
  local target_win = session and session.origin_win or vim.api.nvim_get_current_win()

  local function resume()
    if not suspended then
      return
    end

    vim.schedule(function()
      if state.current == session and not session.closed then
        require("wayfinder").resume_session_ui()
      else
        state.ui_suspended = false
      end
    end)
  end

  if not suspended then
    start(function() end)
    return
  end

  state.ui_suspended = true
  layout.close()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    pcall(vim.api.nvim_set_current_win, target_win)
  end

  vim.schedule(function()
    start(resume)
  end)
end

local function maybe_suspend_ui(opts, start)
  opts = opts or {}
  if opts.suspend == false then
    start(function() end)
    return
  end

  with_suspended_ui(start)
end

local function rerender_trail_state(opts)
  local session = current()
  if not session then
    return
  end

  opts = opts or {}
  if opts.reset_selection then
    session.selection_id = nil
    session.selection_index = 1
  end
  rerender()
end

local function select_saved_trail(prompt, callback, opts)
  maybe_suspend_ui(opts, function(done)
    local names, err = trail_persistence.list()
    if not names then
      persistence_warn(err)
      done()
      return
    end

    if #names == 0 then
      persistence_notice("Wayfinder: No saved Trails")
      done()
      return
    end

    vim.ui.select(names, {
      prompt = prompt,
      format_item = function(name)
        local markers = {}
        if trail_persistence.active_name() == name then
          markers[#markers + 1] = "active"
        end
        if #markers == 0 then
          return name
        end
        return string.format("%s  (%s)", name, table.concat(markers, ", "))
      end,
    }, function(choice)
      if not choice then
        if opts and opts.on_cancel then
          opts.on_cancel()
        end
        done()
        return
      end

      callback(choice, done)
    end)
  end)
end

local function prompt_trail_name(prompt, default, callback, opts)
  maybe_suspend_ui(opts, function(done)
    vim.ui.input({
      prompt = prompt,
      default = default or "",
    }, function(input)
      local name = normalize_name(input)
      if not name then
        if opts and opts.on_cancel then
          opts.on_cancel()
        end
        done()
        return
      end

      callback(name, done)
    end)
  end)
end

local function confirm_overwrite(name, callback, opts)
  maybe_suspend_ui(opts, function(done)
    vim.ui.select({
      "Overwrite",
      "Cancel",
    }, {
      prompt = string.format("Trail '%s' already exists", name),
    }, function(choice)
      if choice ~= "Overwrite" then
        if opts and opts.on_cancel then
          opts.on_cancel()
        end
        done()
        return
      end

      callback(done)
    end)
  end)
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
      open_facet(session, facet.key)
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

function M.trail_save(opts)
  opts = opts or {}
  local finish = opts.on_done or function() end
  local active_name = trail_persistence.active_name()
  if active_name then
    local saved, err = trail_persistence.save_current(nil)
    if not saved then
      if err == "empty" then
        persistence_notice(persistence_error_message(err))
      else
        persistence_warn(err, active_name)
      end
      finish()
      return
    end

    rerender_trail_state()
    persistence_notice(string.format("Saved Trail: %s", saved.name))
    finish()
    return
  end

  M.trail_save_as(opts)
end

function M.trail_save_as(opts)
  opts = opts or {}
  local finish = opts.on_done or function() end
  local default_name = trail_persistence.active_name() or ""

  prompt_trail_name("Save Trail as: ", default_name, function(name, done)
    local saved, err = trail_persistence.save_current_as(name)
    if not saved and err == "name_exists" then
      confirm_overwrite(name, function(confirm_done)
        local overwritten, overwrite_err = trail_persistence.save_current_as(name, { overwrite = true })
        if not overwritten then
          if overwrite_err == "empty" then
            persistence_notice(persistence_error_message(overwrite_err))
          else
            persistence_warn(overwrite_err, name)
          end
          confirm_done()
          done()
          finish()
          return
        end

        rerender_trail_state()
        persistence_notice(string.format("Saved Trail: %s", overwritten.name))
        confirm_done()
        done()
        finish()
      end, { suspend = false, on_cancel = function()
        done()
        finish()
      end })
      return
    end

    if not saved then
      if err == "empty" then
        persistence_notice(persistence_error_message(err))
      else
        persistence_warn(err, name)
      end
      done()
      finish()
      return
    end

    rerender_trail_state()
    persistence_notice(string.format("Saved Trail: %s", saved.name))
    done()
    finish()
  end, { suspend = opts.suspend, on_cancel = finish })
end

function M.trail_load(opts)
  opts = opts or {}
  local finish = opts.on_done or function() end
  select_saved_trail("Load Wayfinder Trail", function(name, done)
    local loaded, err = trail_persistence.load(name)
    if not loaded then
      persistence_warn(err, name)
      done()
      finish()
      return
    end

    rerender_trail_state({ reset_selection = current() and current().facet == "trail" })
    persistence_notice(string.format("Loaded Trail: %s", loaded.name))
    done()
    finish()
  end, { suspend = opts.suspend, on_cancel = finish })
end

local function cycle_saved_trail(delta)
  local loaded, err = trail_persistence.cycle(delta)
  if not loaded then
    if err == "no_saved_trails" then
      persistence_notice(persistence_error_message(err))
    else
      persistence_warn(err)
    end
    return
  end

  rerender_trail_state({ reset_selection = current() and current().facet == "trail" })
  persistence_notice(string.format("Loaded Trail: %s", loaded.name))
end

function M.next_saved_trail()
  cycle_saved_trail(1)
end

function M.prev_saved_trail()
  cycle_saved_trail(-1)
end

function M.trail_delete(opts)
  opts = opts or {}
  local finish = opts.on_done or function() end
  select_saved_trail("Delete Wayfinder Trail", function(name, done)
    local updated, removed = trail_persistence.delete(name)
    if not updated then
      persistence_warn(removed, name)
      done()
      finish()
      return
    end

    if not removed then
      persistence_notice(string.format("Wayfinder: Trail not found: %s", name))
      done()
      finish()
      return
    end

    rerender_trail_state()
    persistence_notice(string.format("Deleted Trail: %s", name))
    done()
    finish()
  end, { suspend = opts.suspend, on_cancel = finish })
end

function M.trail_rename(opts)
  opts = opts or {}
  local finish = opts.on_done or function() end
  select_saved_trail("Rename Wayfinder Trail", function(old_name, select_done)
    prompt_trail_name("Rename Trail to: ", old_name, function(new_name, input_done)
      local renamed, err = trail_persistence.rename(old_name, new_name)
      if not renamed then
        if err == "name_exists" then
          persistence_notice(persistence_error_message(err, new_name))
        else
          persistence_warn(err, old_name)
        end
        input_done()
        select_done()
        finish()
        return
      end

      rerender_trail_state()
      persistence_notice(string.format("Renamed Trail: %s", renamed.name))
      input_done()
      select_done()
      finish()
    end, { suspend = false, on_cancel = function()
      select_done()
      finish()
    end })
  end, { suspend = opts.suspend, on_cancel = finish })
end

function M.trail_menu()
  with_suspended_ui(function(done)
    vim.ui.select({
      "Save Trail",
      "Save Trail As",
      "Load Trail",
      "Rename Trail",
      "Delete Trail",
    }, {
      prompt = "Wayfinder Trail menu",
    }, function(choice)
      if choice == "Save Trail" then
        M.trail_save({ suspend = false, on_done = done })
      elseif choice == "Save Trail As" then
        M.trail_save_as({ suspend = false, on_done = done })
      elseif choice == "Load Trail" then
        M.trail_load({ suspend = false, on_done = done })
      elseif choice == "Rename Trail" then
        M.trail_rename({ suspend = false, on_done = done })
      elseif choice == "Delete Trail" then
        M.trail_delete({ suspend = false, on_done = done })
      else
        done()
      end
    end)
  end)
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
