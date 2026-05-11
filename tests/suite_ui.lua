local t = require("support")

local test = t.test
local assert_ok = t.assert_ok
local wayfinder = t.wayfinder
local actions = t.actions
local state = t.state
local layout = t.layout
local trail = t.trail
local trail_persistence = t.trail_persistence
local fixture_root = t.fixture_root
local open_typescript = t.open_typescript
local preview = require("wayfinder.render.preview")
local async = require("wayfinder.util.async")

test("quickfix export preserves visible order and trail order", function()
  -- Guards quickfix export ordering for both the active facet and Trail.
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, "p")
  local file_a = root .. "/calls.lua"
  local file_b = root .. "/refs.lua"
  vim.fn.writefile({ "local call_item = true" }, file_a)
  vim.fn.writefile({ "local ref_item = true" }, file_b)

  local saved_render = layout.render
  local saved_focus = layout.focus_primary
  ---@diagnostic disable-next-line: duplicate-set-field
  layout.render = function() end
  ---@diagnostic disable-next-line: duplicate-set-field
  layout.focus_primary = function() end

  state.current = {
    facet = "refs",
    visible_items = {
      { id = "refs-b", label = "second", path = file_b, lnum = 1, col = 1, source = "lsp" },
      { id = "refs-a", label = "first", path = file_a, lnum = 1, col = 1, source = "grep" },
    },
  }

  wayfinder.export_quickfix()
  local current_qf = vim.fn.getqflist()
  assert_ok(#current_qf == 2, "expected exported facet quickfix entries")
  assert_ok(
    vim.api.nvim_buf_get_name(current_qf[1].bufnr) == file_b,
    "facet export should preserve visible order"
  )
  assert_ok(
    vim.api.nvim_buf_get_name(current_qf[2].bufnr) == file_a,
    "facet export should preserve visible order"
  )

  trail.clear()
  assert_ok(
    trail.pin({
      id = "trail-a",
      label = "trail a",
      path = file_a,
      lnum = 1,
      col = 1,
      source = "lsp",
    }),
    "pin trail a"
  )
  assert_ok(
    trail.pin({
      id = "trail-b",
      label = "trail b",
      path = file_b,
      lnum = 1,
      col = 1,
      source = "grep",
    }),
    "pin trail b"
  )

  state.current = nil
  wayfinder.export_trail_quickfix()
  local trail_qf = vim.fn.getqflist()
  assert_ok(#trail_qf == 2, "expected exported trail quickfix entries")
  assert_ok(
    vim.api.nvim_buf_get_name(trail_qf[1].bufnr) == file_a,
    "trail export should preserve trail order"
  )
  assert_ok(
    vim.api.nvim_buf_get_name(trail_qf[2].bufnr) == file_b,
    "trail export should preserve trail order"
  )

  layout.render = saved_render
  layout.focus_primary = saved_focus
  state.current = nil
end)

test("wayfinder exits cleanly when the editor is too small", function()
  -- Guards the narrow-window path so Wayfinder warns and aborts instead of crashing on invalid pane sizes.
  local saved_columns = vim.o.columns
  local saved_lines = vim.o.lines

  local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  vim.o.columns = 60
  vim.o.lines = 14

  local ok, err = pcall(wayfinder.open)

  vim.o.columns = saved_columns
  vim.o.lines = saved_lines

  assert_ok(ok, err or "expected Wayfinder to fail gracefully in a small editor")
  assert_ok(state.current == nil, "small editor open should not leave an active Wayfinder session")
end)

test("facet switches restore the last selected item within the current session", function()
  -- Guards per-facet selection memory so hopping between facets feels stable without persisting across new opens.
  local saved_render = layout.render
  local saved_focus = layout.focus_primary
  ---@diagnostic disable-next-line: duplicate-set-field
  layout.render = function() end
  ---@diagnostic disable-next-line: duplicate-set-field
  layout.focus_primary = function() end

  state.current = {
    facet = "refs",
    auto_facet_pending = false,
    filter = "",
    selection_index = 2,
    selection_id = "ref-2",
    facet_memory = {
      refs = { id = "ref-2", index = 2 },
    },
    visible_items = {
      { id = "ref-1", facet = "refs", label = "ref one" },
      { id = "ref-2", facet = "refs", label = "ref two" },
    },
    remember_facet_selection = function(self)
      self.facet_memory = self.facet_memory or {}
      self.facet_memory[self.facet] = {
        id = self.selection_id,
        index = self.selection_index,
      }
    end,
    refresh_visible = function(self)
      if self.facet == "tests" then
        self.visible_items = {
          { id = "test-1", facet = "tests", label = "test one" },
          { id = "test-2", facet = "tests", label = "test two" },
        }
      else
        self.visible_items = {
          { id = "ref-1", facet = "refs", label = "ref one" },
          { id = "ref-2", facet = "refs", label = "ref two" },
        }
      end

      if self.selection_id then
        for index, item in ipairs(self.visible_items) do
          if item.id == self.selection_id then
            self.selection_index = index
            self:remember_facet_selection()
            return
          end
        end
      end

      self.selection_index = math.min(self.selection_index or 1, #self.visible_items)
      self.selection_id = self.visible_items[self.selection_index].id
      self:remember_facet_selection()
    end,
  }

  actions.next_facet()
  assert_ok(state.current.facet == "tests", "expected switch into tests facet")
  assert_ok(
    state.current.selection_id == "test-1",
    "expected new facet to start at first visible item"
  )

  actions.select_next()
  assert_ok(state.current.selection_id == "test-2", "expected test facet selection to move")

  actions.prev_facet()
  assert_ok(state.current.facet == "refs", "expected switch back into refs facet")
  assert_ok(
    state.current.selection_id == "ref-2",
    "expected refs facet to restore its previous selection"
  )
  assert_ok(state.current.selection_index == 2, "expected refs facet to restore its previous index")

  layout.render = saved_render
  layout.focus_primary = saved_focus
  state.current = nil
end)

test("top bar shows saved Trail count even before the working Trail has items", function()
  -- Guards the saved-Trail affordance so users can discover project Trails before building a new working Trail.
  local saved_count = trail_persistence.saved_count
  ---@diagnostic disable-next-line: duplicate-set-field
  trail_persistence.saved_count = function()
    return 2
  end

  local session = {
    mode = "symbol",
    subject = "createUser",
    path = fixture_root .. "/src/user_service.ts",
    project_root = fixture_root,
    cwd = fixture_root,
    scope = { mode = "project", label = nil },
    facet = "calls",
    filter = "",
    selection_index = 1,
    selection_id = nil,
    visible_items = {},
    counts = {
      all = 0,
      calls = 0,
      refs = 0,
      tests = 0,
      git = 0,
      trail = 0,
    },
    loading = false,
    show_details = false,
    row_actions = {},
    list_line_count = 0,
  }

  state.current = session
  state.reset_trail_persistence()
  state.notice = { text = nil, expires_at = 0 }
  layout.render(session)

  local top_lines = vim.api.nvim_buf_get_lines(state.ui.top_buf, 0, -1, false)
  assert_ok(
    string.find(top_lines[1] or "", "Trail %(2 saved%)", 1) ~= nil,
    "expected saved Trail count in top bar"
  )

  layout.close()
  trail_persistence.saved_count = saved_count
  state.current = nil
end)

test("top bar fits available width with long status segments", function()
  -- Guards the compact chrome so long subject/filter/reason/Trail text does not overflow the top bar.
  local saved_count = trail_persistence.saved_count
  ---@diagnostic disable-next-line: duplicate-set-field
  trail_persistence.saved_count = function()
    return 12
  end

  local session = {
    mode = "symbol",
    subject = "createUserWithAnExtremelyLongNameThatShouldNotTakeTheWholeTopBar",
    path = fixture_root .. "/src/user_service.ts",
    project_root = fixture_root,
    cwd = fixture_root,
    scope = { mode = "package", label = "package scope" },
    facet = "refs",
    filter = '"very long filter phrase" !generated',
    selection_index = 1,
    selection_id = "ref-1",
    visible_items = {
      {
        id = "ref-1",
        facet = "refs",
        label = "reference",
        path = fixture_root .. "/src/user_service.ts",
        lnum = 1,
        reason = "plain text fallback with a long explanation",
      },
    },
    counts = {
      all = 1,
      calls = 0,
      refs = 1,
      tests = 0,
      git = 0,
      trail = 3,
    },
    loading = true,
    show_details = false,
    row_actions = {},
    list_line_count = 0,
  }

  state.current = session
  state.attach_saved_trail("long saved Trail name that should be truncated", {
    project_root = fixture_root,
    dirty = true,
  })
  layout.render(session)

  local top_line = vim.api.nvim_buf_get_lines(state.ui.top_buf, 0, 1, false)[1] or ""
  local top_width = vim.api.nvim_win_get_width(state.ui.top)
  assert_ok(
    vim.fn.strdisplaywidth(top_line) <= top_width,
    "expected top bar text to fit inside its window"
  )

  layout.close()
  trail_persistence.saved_count = saved_count
  state.reset_trail_persistence()
  state.current = nil
end)

test("git preview ignores stale async callbacks after selection changes", function()
  -- Guards fast list movement so a slow git preview cannot overwrite the current file preview.
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, "p")
  local file = root .. "/current.ts"
  vim.fn.writefile({
    "export function currentPreview() {",
    '  return "current";',
    "}",
  }, file)

  local session = {
    mode = "symbol",
    subject = "currentPreview",
    path = file,
    project_root = root,
    cwd = root,
    selection_index = 1,
    visible_items = {},
  }
  local git_item = {
    id = "git-old",
    source = "git",
    path = file,
    lnum = 1,
    git = {
      hash = "abcdef123456",
      relative = "current.ts",
      repo_root = root,
    },
  }
  local file_item = {
    id = "file-current",
    source = "lsp",
    path = file,
    lnum = 1,
    preview_range = { start = 1, ["end"] = 3 },
  }
  session.visible_items = { git_item, file_item }

  local saved_system = async.system
  local pending
  ---@diagnostic disable-next-line: duplicate-set-field
  async.system = function(_, _, callback)
    pending = callback
  end

  state.current = session
  layout.open()
  preview.render(session, state.ui.preview, git_item)
  assert_ok(type(pending) == "function", "expected git preview callback to be pending")

  session.selection_index = 2
  preview.render(session, state.ui.preview, file_item)
  pending({
    code = 0,
    stdout = 'export const staleGitPreview = "stale";',
    stderr = "",
  })

  local preview_lines =
    table.concat(vim.api.nvim_buf_get_lines(state.ui.preview_buf, 0, -1, false), "\n")
  assert_ok(
    preview_lines:find("currentPreview", 1, true) ~= nil,
    "expected current file preview to remain visible"
  )
  assert_ok(
    preview_lines:find("staleGitPreview", 1, true) == nil,
    "stale git preview should not overwrite the selected item preview"
  )

  async.system = saved_system
  layout.close()
  state.current = nil
end)

test("explore selected item re-roots the session without changing Trail", function()
  -- Guards the explicit exploration pivot so users can walk connected code without auto-pinning.
  local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
  t.start_demo_lsp(bufnr, fixture_root)
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  trail.clear()
  assert_ok(
    trail.pin({
      id = "trail-create-user",
      label = "createUser",
      path = fixture_root .. "/src/user_service.ts",
      lnum = 1,
      col = 17,
      source = "lsp",
    }),
    "pin initial trail item"
  )

  wayfinder.open()
  wayfinder.explore({
    id = "target-find-user",
    label = "export function findUser(id: string) {",
    path = fixture_root .. "/src/user_service.ts",
    lnum = 8,
    col = 18,
    source = "lsp",
  })

  assert_ok(state.current ~= nil, "expected active Wayfinder session after explore")
  assert_ok(state.current.subject == "findUser", "expected explore to re-root on target symbol")
  assert_ok(
    state.notice.text == "Exploring findUser",
    "explore notice should use the detected symbol, not the full row label"
  )
  assert_ok(state.current.facet == "calls", "expected symbol explore to start on Calls")
  assert_ok(#trail.items() == 1, "explore should not mutate Trail")
  assert_ok(
    trail.items()[1].id == "trail-create-user",
    "explore should preserve existing Trail items"
  )

  t.await(function()
    return state.current and state.current.loading == false
  end, 2000, "explored session did not finish loading")

  local facets = {}
  for _, item in ipairs(state.current.items) do
    facets[item.facet] = true
  end
  assert_ok(facets.calls, "expected explored session to gather calls")
  assert_ok(facets.refs, "expected explored session to gather refs")

  layout.close()
  if state.current and state.current.cancel then
    state.current:cancel()
  end
  state.current = nil
end)

test("explore ignores git history rows because they are not code locations", function()
  -- Guards exploration so file-history rows do not accidentally pivot on the first word of a file.
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, "p")
  local file = root .. "/service.ts"
  vim.fn.writefile({
    "export function createUser() {",
    "  return true;",
    "}",
  }, file)

  state.current = {
    subject = "createUser",
    path = file,
    cwd = root,
    project_root = root,
    bufnr = vim.api.nvim_get_current_buf(),
    origin_win = vim.api.nvim_get_current_win(),
  }

  wayfinder.explore({
    id = "git-row",
    source = "git",
    kind = "commit",
    label = "fixture commit",
    path = file,
    lnum = 1,
    col = 1,
  })

  assert_ok(state.current.subject == "createUser", "git row explore should leave session unchanged")
  state.current = nil
end)

test("explore history moves back and forward without changing Trail", function()
  -- Guards the reversible explore loop while keeping it separate from pinned Trail state.
  local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
  t.start_demo_lsp(bufnr, fixture_root)
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  trail.clear()
  assert_ok(
    trail.pin({
      id = "trail-create-user",
      label = "createUser",
      path = fixture_root .. "/src/user_service.ts",
      lnum = 1,
      col = 17,
      source = "lsp",
    }),
    "pin initial trail item"
  )

  wayfinder.open()
  assert_ok(state.current.subject == "createUser", "expected initial subject")

  wayfinder.explore({
    id = "target-find-user",
    label = "export function findUser(id: string) {",
    path = fixture_root .. "/src/user_service.ts",
    lnum = 8,
    col = 18,
    source = "lsp",
  })
  assert_ok(state.current.subject == "findUser", "expected first explore target")
  assert_ok(#state.current.history.back == 1, "expected one explore back entry")
  assert_ok(#state.current.history.forward == 0, "expected empty explore forward stack")

  wayfinder.explore({
    id = "target-update-user",
    label = "export function updateUser(id: string, name: string) {",
    path = fixture_root .. "/src/user_service.ts",
    lnum = 15,
    col = 18,
    source = "lsp",
  })
  assert_ok(state.current.subject == "updateUser", "expected second explore target")
  assert_ok(#state.current.history.back == 2, "expected two explore back entries")

  wayfinder.explore_back()
  assert_ok(state.current.subject == "findUser", "expected back to previous target")
  assert_ok(#state.current.history.back == 1, "expected one remaining back entry")
  assert_ok(#state.current.history.forward == 1, "expected one forward entry")

  wayfinder.explore_back()
  assert_ok(state.current.subject == "createUser", "expected back to initial target")
  assert_ok(#state.current.history.back == 0, "expected no remaining back entries")
  assert_ok(#state.current.history.forward == 2, "expected two forward entries")

  wayfinder.explore_forward()
  assert_ok(state.current.subject == "findUser", "expected forward to next target")
  assert_ok(#state.current.history.back == 1, "expected back entry after forward")
  assert_ok(#state.current.history.forward == 1, "expected one remaining forward entry")
  assert_ok(#trail.items() == 1, "explore history should not mutate Trail")

  layout.close()
  if state.current and state.current.cancel then
    state.current:cancel()
  end
  state.current = nil
end)
