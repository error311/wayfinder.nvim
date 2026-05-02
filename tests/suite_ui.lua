local t = require("support")

local test = t.test
local assert_ok = t.assert_ok
local wayfinder = t.wayfinder
local state = t.state
local layout = t.layout
local trail = t.trail
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
  assert_ok(vim.api.nvim_buf_get_name(current_qf[1].bufnr) == file_b, "facet export should preserve visible order")
  assert_ok(vim.api.nvim_buf_get_name(current_qf[2].bufnr) == file_a, "facet export should preserve visible order")

  trail.clear()
  assert_ok(trail.pin({ id = "trail-a", label = "trail a", path = file_a, lnum = 1, col = 1, source = "lsp" }), "pin trail a")
  assert_ok(trail.pin({ id = "trail-b", label = "trail b", path = file_b, lnum = 1, col = 1, source = "grep" }), "pin trail b")

  state.current = nil
  wayfinder.export_trail_quickfix()
  local trail_qf = vim.fn.getqflist()
  assert_ok(#trail_qf == 2, "expected exported trail quickfix entries")
  assert_ok(vim.api.nvim_buf_get_name(trail_qf[1].bufnr) == file_a, "trail export should preserve trail order")
  assert_ok(vim.api.nvim_buf_get_name(trail_qf[2].bufnr) == file_b, "trail export should preserve trail order")

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
