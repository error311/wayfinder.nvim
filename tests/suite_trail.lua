local t = require("support")

local test = t.test
local assert_ok = t.assert_ok
local wayfinder = t.wayfinder
local state = t.state
local trail = t.trail
local trail_persistence = t.trail_persistence
local trail_store = t.trail_store
local git_fixture_root = t.git_fixture_root

test("trail pins and removes items", function()
  -- Guards the basic Trail pin/remove state so later workflow changes do not break it.
  trail.clear()
  assert_ok(trail.pin({ id = "one", label = "one" }), "pin should succeed")
  assert_ok(trail.has("one"), "trail should contain item")
  assert_ok(trail.remove("one"), "remove should succeed")
end)

test("trail navigation skips invalid items and wraps", function()
  -- Guards external Trail navigation when entries are missing on disk and when cursor movement wraps.
  trail.clear()

  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, "p")
  local file_a = root .. "/a.lua"
  local file_b = root .. "/b.lua"
  vim.fn.writefile({ "local a = true" }, file_a)
  vim.fn.writefile({ "local b = true" }, file_b)

  assert_ok(trail.pin({ id = "missing", label = "missing", path = root .. "/missing.lua", lnum = 1, col = 1 }), "pin missing")
  assert_ok(trail.pin({ id = "a", label = "a", path = file_a, lnum = 1, col = 1 }), "pin a")
  assert_ok(trail.pin({ id = "b", label = "b", path = file_b, lnum = 1, col = 1 }), "pin b")

  wayfinder.trail_next()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_a, "trail next should wrap to first valid item")

  wayfinder.trail_prev()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_b, "trail prev should wrap back to previous valid item")

  wayfinder.trail_open()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_b, "trail open should reopen current trail item")
end)

test("external Trail traversal still works after loading a saved Trail", function()
  -- Guards the saved-Trail workflow end to end so load does not break next/prev/open behavior outside the UI.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root
  local file_a = project_root .. "/src/user_service.ts"
  local file_b = project_root .. "/tests/user_service_test.ts"

  assert(trail_store.set(project_root, {
    name = "auth bug",
    items = {
      { id = "trail-a", label = "trail a", path = file_a, lnum = 1, col = 1 },
      { id = "trail-b", label = "trail b", path = file_b, lnum = 1, col = 1 },
    },
  }, { state_root = state_root }))

  assert(trail_persistence.load("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))

  wayfinder.trail_open()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_a, "trail open should target first loaded item")

  wayfinder.trail_next()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_b, "trail next should move through loaded Trail")

  wayfinder.trail_prev()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_a, "trail prev should move back through loaded Trail")
end)

test("loaded Trail traversal skips stale missing paths safely", function()
  -- Guards saved-Trail traversal when old entries no longer exist on disk after a later session.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root
  local missing = project_root .. "/missing_after_load.ts"
  local file_a = project_root .. "/src/user_service.ts"
  local file_b = project_root .. "/tests/user_service_test.ts"

  assert(trail_store.set(project_root, {
    name = "stale trail",
    items = {
      { id = "missing", label = "missing", path = missing, lnum = 1, col = 1 },
      { id = "trail-a", label = "trail a", path = file_a, lnum = 1, col = 1 },
      { id = "trail-b", label = "trail b", path = file_b, lnum = 1, col = 1 },
    },
  }, { state_root = state_root }))

  assert(trail_persistence.load("stale trail", {
    project_root = project_root,
    state_root = state_root,
  }))

  wayfinder.trail_open()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_a, "trail open should skip missing first entry")

  wayfinder.trail_next()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_b, "trail next should continue to next valid entry")

  wayfinder.trail_prev()
  assert_ok(vim.api.nvim_buf_get_name(0) == file_a, "trail prev should move back among valid entries")
end)

test("trail mutations mark saved and detached working Trails dirty", function()
  -- Guards active Trail semantics so post-load edits become visibly unsaved instead of silently mutating clean state.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  trail.clear({ dirty = false })
  state.reset_trail_persistence()
  assert_ok(trail.pin({ id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 }), "pin trail a")
  assert_ok(state.trail_persistence.dirty == true, "expected detached Trail pin to mark dirty")

  assert(trail_persistence.save_current("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(state.trail_persistence.dirty == false, "expected save to reset dirty state")

  assert_ok(trail.pin({ id = "trail-b", label = "trail b", path = project_root .. "/tests/user_service_test.ts", lnum = 1, col = 1 }), "pin trail b")
  assert_ok(state.trail_persistence.active_name == "auth bug", "expected active saved Trail to stay attached after mutation")
  assert_ok(state.trail_persistence.dirty == true, "expected attached Trail pin to mark dirty")

  assert_ok(trail.remove("trail-b"), "remove trail b")
  assert_ok(state.trail_persistence.dirty == true, "expected remove to preserve dirty state")

  assert(trail_persistence.load("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(state.trail_persistence.dirty == false, "expected load to restore clean saved state")

  trail.clear()
  assert_ok(state.trail_persistence.active_name == "auth bug", "expected clear to keep active saved Trail association")
  assert_ok(state.trail_persistence.dirty == true, "expected clear to mark attached Trail dirty")
end)
