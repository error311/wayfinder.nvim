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
