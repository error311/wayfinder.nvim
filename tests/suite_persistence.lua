local t = require("support")

local test = t.test
local assert_ok = t.assert_ok
local state = t.state
local trail = t.trail
local trail_persistence = t.trail_persistence
local trail_store = t.trail_store
local git_fixture_root = t.git_fixture_root

test("trail persistence state tracks saved detach and dirty metadata", function()
  -- Guards the new persistent-Trail state model before storage is added on top of it.
  state.reset_trail_persistence()

  local meta = state.trail_persistence_state()
  assert_ok(meta.active_name == nil, "expected no active saved Trail by default")
  assert_ok(meta.detached == true, "expected Trail to start detached")
  assert_ok(meta.dirty == false, "expected clean Trail persistence state by default")

  state.attach_saved_trail("auth bug", { project_root = git_fixture_root })
  meta = state.trail_persistence_state()
  assert_ok(meta.active_name == "auth bug", "expected attached saved Trail name")
  assert_ok(meta.project_root == vim.fs.normalize(git_fixture_root), "expected attached saved Trail project root")
  assert_ok(meta.detached == false, "expected attached saved Trail state")
  assert_ok(meta.dirty == false, "expected attached Trail to start clean")

  state.mark_trail_dirty()
  meta = state.trail_persistence_state()
  assert_ok(meta.dirty == true, "expected dirty Trail state after mutation marker")

  state.detach_trail({ dirty = true })
  meta = state.trail_persistence_state()
  assert_ok(meta.active_name == nil, "expected detached Trail to drop saved name")
  assert_ok(meta.project_root == nil, "expected detached Trail to drop saved project root")
  assert_ok(meta.detached == true, "expected detached Trail state")
  assert_ok(meta.dirty == true, "expected detached dirty flag to preserve explicit state")

  state.reset_trail_persistence()
end)

test("trail store reads missing project storage as empty data", function()
  -- Guards the initial persistent-Trail file behavior so missing storage does not error or invent state.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  local data = assert(trail_store.read_project(project_root, { state_root = state_root }))
  assert_ok(data.project_root == vim.fs.normalize(project_root), "expected stored project root")
  assert_ok(vim.deep_equal(data.trails, {}), "expected no saved trails by default")
  assert_ok(data.last_active == nil, "expected no last active trail by default")
end)

test("trail store persists and lists named trails per project", function()
  -- Guards the helper storage layer so named Trails can be written and read back before commands/UI are added.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  local written = assert(trail_store.set(project_root, {
    name = "auth bug",
    items = {
      { id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 },
      { id = "trail-b", label = "trail b", path = project_root .. "/tests/user_service_test.ts", lnum = 1, col = 1 },
    },
  }, { state_root = state_root }))

  assert_ok(written.trails["auth bug"] ~= nil, "expected saved trail entry")
  assert_ok(#written.trails["auth bug"].items == 2, "expected saved trail items")

  local names = assert(trail_store.list(project_root, { state_root = state_root }))
  assert_ok(vim.deep_equal(names, { "auth bug" }), "expected named trail listing")

  local loaded = assert(trail_store.get(project_root, "auth bug", { state_root = state_root }))
  assert_ok(loaded.name == "auth bug", "expected named trail lookup")
  assert_ok(loaded.items[1].id == "trail-a", "expected trail order to persist")
  assert_ok(loaded.items[2].id == "trail-b", "expected trail order to persist")
end)

test("trail store keeps durable item fields and strips row-only fields", function()
  -- Guards the persisted item shape so saved Trails keep useful preview/export data without UI junk.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  assert(trail_store.set(project_root, {
    name = "git trail",
    items = {
      {
        id = "git-item",
        path = project_root .. "/src/user_service.ts",
        lnum = 1,
        col = 1,
        label = "fixture: add fallback copy",
        secondary = "src/user_service.ts",
        detail = "abcd123 • 1 minute ago",
        facet = "git",
        kind = "commit",
        source = "git",
        reason = "recent commit touching current file",
        badge = "GIT",
        preview_range = { start = 1, ["end"] = 10 },
        git = {
          hash = "abcd123",
          relative = "src/user_service.ts",
          repo_root = project_root,
        },
        score = 999,
        icon = "⎇",
        group = "Recent Commits",
        pinned = true,
      },
    },
  }, { state_root = state_root }))

  local loaded = assert(trail_store.get(project_root, "git trail", { state_root = state_root }))
  local item = loaded.items[1]

  assert_ok(item.reason == "recent commit touching current file", "expected reason to persist")
  assert_ok(item.preview_range and item.preview_range.start == 1 and item.preview_range["end"] == 10, "expected preview range to persist")
  assert_ok(item.git and item.git.hash == "abcd123", "expected git preview metadata to persist")
  assert_ok(item.score == nil, "expected transient score to be stripped")
  assert_ok(item.icon == nil, "expected transient icon to be stripped")
  assert_ok(item.group == nil, "expected transient group to be stripped")
  assert_ok(item.pinned == nil, "expected transient pinned flag to be stripped")
end)

test("trail store deletes saved trails without touching other entries", function()
  -- Guards helper deletion semantics so removing one saved Trail does not wipe the whole project file.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  assert(trail_store.set(project_root, {
    name = "auth bug",
    items = { { id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 } },
  }, { state_root = state_root }))

  assert(trail_store.set(project_root, {
    name = "refactor targets",
    items = { { id = "trail-b", label = "trail b", path = project_root .. "/tests/user_service_test.ts", lnum = 1, col = 1 } },
  }, { state_root = state_root }))

  local _, removed = assert(trail_store.delete(project_root, "auth bug", { state_root = state_root }))
  assert_ok(removed == true, "expected saved trail deletion")

  local names = assert(trail_store.list(project_root, { state_root = state_root }))
  assert_ok(vim.deep_equal(names, { "refactor targets" }), "expected other saved trail to remain")
end)

test("trail store keeps empty saved-trails JSON as an object after deleting the last entry", function()
  -- Guards the on-disk JSON shape so deleting the last saved Trail does not turn the trails map into an array.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  assert(trail_store.set(project_root, {
    name = "auth bug",
    items = { { id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 } },
  }, { state_root = state_root }))

  local updated, removed = assert(trail_store.delete(project_root, "auth bug", { state_root = state_root }))
  assert_ok(removed == true, "expected final saved Trail deletion")
  assert_ok(vim.tbl_isempty(updated.trails), "expected no saved trails after final delete")

  local storage_file = assert(trail_store.project_file(project_root, { state_root = state_root }))
  local raw = table.concat(vim.fn.readfile(storage_file), "\n")
  local decoded = assert(vim.json.decode(raw))
  assert_ok(type(decoded.trails) == "table" and next(decoded.trails) == nil, "expected empty decoded trails table")
  assert_ok(string.find(raw, [["trails":{}]], 1, true) ~= nil, "expected trails to persist as an empty object")
end)

test("trail store fails safely on invalid project storage", function()
  -- Guards corrupt-storage behavior so persistence failures stay contained and predictable.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root
  local storage_file = assert(trail_store.project_file(project_root, { state_root = state_root }))
  vim.fn.mkdir(vim.fs.dirname(storage_file), "p")
  vim.fn.writefile({ "{not valid json" }, storage_file)

  local data, err = trail_store.read_project(project_root, { state_root = state_root })
  assert_ok(data == nil, "expected invalid storage read to fail")
  assert_ok(err == "invalid_json", "expected invalid storage error")
end)

test("trail persistence refuses to save an empty Trail", function()
  -- Guards the explicit-save flow so persistence stays opt-in and empty Trails do not create junk storage.
  trail.clear()
  state.reset_trail_persistence()

  local saved, err = trail_persistence.save_current("auth bug", {
    project_root = git_fixture_root,
    state_root = vim.fs.normalize(vim.fn.tempname()),
  })

  assert_ok(saved == nil, "expected empty Trail save to refuse")
  assert_ok(err == "empty", "expected empty Trail error")
end)

test("trail persistence saves current Trail and reuses active saved name", function()
  -- Guards the core save flow before commands/UI are added on top of it.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  trail.clear()
  state.reset_trail_persistence()
  assert_ok(trail.pin({ id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 }), "pin trail a")
  assert_ok(trail.pin({ id = "trail-b", label = "trail b", path = project_root .. "/tests/user_service_test.ts", lnum = 1, col = 1 }), "pin trail b")

  local saved = assert(trail_persistence.save_current("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(saved.name == "auth bug", "expected saved Trail name")
  assert_ok(state.trail_persistence.active_name == "auth bug", "expected active saved Trail name after save")
  assert_ok(state.trail_persistence.detached == false, "expected attached state after save")
  assert_ok(state.trail_persistence.dirty == false, "expected clean state after save")

  local names = assert(trail_persistence.list({
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(vim.deep_equal(names, { "auth bug" }), "expected saved Trail listing")

  assert_ok(trail.pin({ id = "trail-c", label = "trail c", path = project_root .. "/src/user_service.ts", lnum = 2, col = 1 }), "pin trail c")
  local updated = assert(trail_persistence.save_current(nil, {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(#updated.items == 3, "expected active saved name reuse on save")
end)

test("trail persistence save as refuses duplicate saved names", function()
  -- Guards explicit naming semantics so Save As does not silently overwrite another saved Trail.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  assert(trail_store.set(project_root, {
    name = "auth bug",
    items = { { id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 } },
  }, { state_root = state_root }))

  trail.clear({ dirty = false })
  state.reset_trail_persistence()
  assert_ok(trail.pin({ id = "trail-b", label = "trail b", path = project_root .. "/tests/user_service_test.ts", lnum = 1, col = 1 }), "pin trail b")

  local saved, err = trail_persistence.save_current_as("auth bug", {
    project_root = project_root,
    state_root = state_root,
  })
  assert_ok(saved == nil, "expected duplicate save-as to refuse")
  assert_ok(err == "name_exists", "expected duplicate name error")
end)

test("trail persistence only reuses active saved names inside the same project", function()
  -- Guards against cross-project state leaks so Save Trail does not silently reuse a saved name from another repo.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root_a = git_fixture_root
  local project_root_b = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(project_root_b, "p")
  vim.fn.writefile({ "export const other = 1" }, project_root_b .. "/other.ts")

  trail.clear({ dirty = false })
  state.reset_trail_persistence()
  assert_ok(trail.pin({ id = "trail-a", label = "trail a", path = project_root_a .. "/src/user_service.ts", lnum = 1, col = 1 }), "pin trail a")
  assert(trail_persistence.save_current("auth bug", {
    project_root = project_root_a,
    state_root = state_root,
  }))

  assert_ok(trail_persistence.active_name({
    project_root = project_root_a,
    state_root = state_root,
  }) == "auth bug", "expected active name lookup in original project")
  assert_ok(trail_persistence.active_name({
    project_root = project_root_b,
    state_root = state_root,
  }) == nil, "expected no active saved name reuse in another project")

  local saved, err = trail_persistence.save_current(nil, {
    project_root = project_root_b,
    state_root = state_root,
  })
  assert_ok(saved == nil, "expected cross-project save without explicit name to refuse")
  assert_ok(err == "missing_name", "expected cross-project save to require a new name")
end)

test("trail persistence cycles saved Trails within the current project", function()
  -- Guards direct saved-Trail cycling so bracket keys can move through named Trails without reopening the menu.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  assert(trail_store.set(project_root, {
    name = "alpha",
    items = {
      { id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 },
    },
  }, { state_root = state_root }))
  assert(trail_store.set(project_root, {
    name = "beta",
    items = {
      { id = "trail-b", label = "trail b", path = project_root .. "/tests/user_service_test.ts", lnum = 1, col = 1 },
    },
  }, { state_root = state_root }))

  trail.clear({ dirty = false })
  state.reset_trail_persistence()

  local first = assert(trail_persistence.cycle(1, {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(first.name == "alpha", "expected forward cycle without active Trail to start at first saved Trail")
  assert_ok(state.trail_persistence.active_name == "alpha", "expected first cycle to attach first saved Trail")

  local next_loaded = assert(trail_persistence.cycle(1, {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(next_loaded.name == "beta", "expected forward cycle to advance to next saved Trail")

  local wrapped = assert(trail_persistence.cycle(1, {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(wrapped.name == "alpha", "expected forward cycle to wrap")

  local prev_loaded = assert(trail_persistence.cycle(-1, {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(prev_loaded.name == "beta", "expected backward cycle to wrap from first to last")
end)

test("trail persistence load replaces the working Trail in order", function()
  -- Guards the first load flow so saved Trails restore into live Trail traversal cleanly.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  assert(trail_store.set(project_root, {
    name = "auth bug",
    items = {
      { id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 },
      { id = "trail-b", label = "trail b", path = project_root .. "/tests/user_service_test.ts", lnum = 1, col = 1 },
    },
  }, { state_root = state_root }))

  trail.clear()
  state.reset_trail_persistence()
  assert_ok(trail.pin({ id = "old", label = "old", path = project_root .. "/src/user_service.ts", lnum = 9, col = 1 }), "pin old")

  local loaded = assert(trail_persistence.load("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(loaded.name == "auth bug", "expected loaded Trail")
  assert_ok(state.trail_persistence.active_name == "auth bug", "expected active saved name after load")
  assert_ok(state.trail_persistence.detached == false, "expected attached state after load")
  assert_ok(state.trail_persistence.dirty == false, "expected clean state after load")

  local items = trail.items()
  assert_ok(#items == 2, "expected working Trail replacement")
  assert_ok(items[1].id == "trail-a", "expected loaded Trail order")
  assert_ok(items[2].id == "trail-b", "expected loaded Trail order")
  assert_ok(trail.cursor() == 1, "expected Trail cursor reset on load")
end)

test("trail persistence delete detaches the active saved Trail", function()
  -- Guards delete semantics so removing the saved entry does not destroy the current working Trail.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  trail.clear()
  state.reset_trail_persistence()
  assert_ok(trail.pin({ id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 }), "pin trail a")
  assert(trail_persistence.save_current("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))

  local _, removed = assert(trail_persistence.delete("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(removed == true, "expected saved Trail deletion")
  assert_ok(state.trail_persistence.active_name == nil, "expected deleted active Trail to detach")
  assert_ok(state.trail_persistence.detached == true, "expected detached state after deleting active saved Trail")
  assert_ok(#trail.items() == 1, "expected working Trail items to remain after delete")
end)

test("trail persistence rename updates saved and active trail names", function()
  -- Guards rename before commands/UI are added so saved Trail naming stays predictable and non-destructive.
  local state_root = vim.fs.normalize(vim.fn.tempname())
  local project_root = git_fixture_root

  trail.clear({ dirty = false })
  state.reset_trail_persistence()
  assert_ok(trail.pin({ id = "trail-a", label = "trail a", path = project_root .. "/src/user_service.ts", lnum = 1, col = 1 }), "pin trail a")
  assert(trail_persistence.save_current("auth bug", {
    project_root = project_root,
    state_root = state_root,
  }))

  local renamed = assert(trail_persistence.rename("auth bug", "auth bug v2", {
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(renamed.name == "auth bug v2", "expected renamed saved Trail")
  assert_ok(state.trail_persistence.active_name == "auth bug v2", "expected active saved Trail name to update on rename")

  local names = assert(trail_persistence.list({
    project_root = project_root,
    state_root = state_root,
  }))
  assert_ok(vim.deep_equal(names, { "auth bug v2" }), "expected renamed saved Trail list")
end)
