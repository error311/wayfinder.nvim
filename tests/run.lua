vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.swapfile = false
vim.notify = function() end

local wayfinder = require("wayfinder")
local state = require("wayfinder.state")
local layout = require("wayfinder.layout")
local trail = require("wayfinder.trail")
local lsp_source = require("wayfinder.sources.lsp")
local tests_source = require("wayfinder.sources.tests")
local git_source = require("wayfinder.sources.git")
local filter_util = require("wayfinder.util.filter")
local scope_util = require("wayfinder.util.scope")

wayfinder.setup()

-- Harness -------------------------------------------------------------------

local failures = {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("ok   " .. name)
  else
    print("FAIL " .. name)
    print(err)
    table.insert(failures, name)
  end
end

local function assert_ok(value, message)
  if not value then
    error(message or "assertion failed", 0)
  end
end

local function await(predicate, timeout_ms, message)
  local finished = vim.wait(timeout_ms or 2000, predicate)
  assert_ok(finished, message or "timed out waiting for async work")
end

local function await_callback(start, validate, opts)
  opts = opts or {}

  local done = false
  local callback_err = nil
  local result

  local handle = start(function(items)
    result = items
    local _, err = pcall(validate, items)
    callback_err = err
    done = true
  end)

  await(function()
    return done
  end, opts.timeout_ms, opts.message)

  if callback_err then
    error(callback_err, 0)
  end

  return result, handle
end

-- Fixtures ------------------------------------------------------------------

local fixture_root = vim.fs.normalize(vim.fn.getcwd() .. "/demo/fixture-app")

local function run_system(args, cwd)
  vim.fn.system(args, cwd)
  assert_ok(vim.v.shell_error == 0, "command failed: " .. table.concat(args, " "))
end

local function make_git_fixture()
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.mkdir(root .. "/tests", "p")

  vim.fn.writefile({
    "{",
    '  "name": "wayfinder-test-fixture",',
    '  "private": true',
    "}",
  }, root .. "/package.json")

  vim.fn.writefile({
    "export function createUser(name) {",
    "  return { id: name.toLowerCase(), name };",
    "}",
    "",
    'export const USER_ACTION = "createUser";',
  }, root .. "/src/user_service.ts")

  vim.fn.writefile({
    'import { createUser } from "../src/user_service";',
    "",
    'describe("createUser", () => {',
    '  it("creates a user", () => {',
    '    expect(createUser("Ryan").id).toBe("ryan");',
    "  });",
    "});",
  }, root .. "/tests/user_service_test.ts")

  run_system({ "git", "init", "-b", "main", root })
  run_system({ "git", "-C", root, "config", "user.name", "Wayfinder Tests" })
  run_system({ "git", "-C", root, "config", "user.email", "wayfinder@example.com" })
  run_system({ "git", "-C", root, "add", "." })
  run_system({ "git", "-C", root, "commit", "-m", "fixture: initial" })

  vim.fn.writefile({
    "export function createUser(name) {",
    "  return { id: name.toLowerCase(), name };",
    "}",
    "",
    'export const USER_ACTION = "createUser";',
    'export const USER_COPY = "createUser helps bootstrap demos.";',
  }, root .. "/src/user_service.ts")

  run_system({ "git", "-C", root, "add", "src/user_service.ts" })
  run_system({ "git", "-C", root, "commit", "-m", "fixture: add fallback copy" })

  return root
end

local git_fixture_root = make_git_fixture()

local function make_monorepo_fixture()
  local root = vim.fs.normalize(vim.fn.tempname())
  local web_root = root .. "/apps/web"
  local admin_root = root .. "/apps/admin"

  vim.fn.mkdir(web_root .. "/src", "p")
  vim.fn.mkdir(web_root .. "/tests", "p")
  vim.fn.mkdir(admin_root .. "/src", "p")
  vim.fn.mkdir(admin_root .. "/tests", "p")

  vim.fn.writefile({ '{ "name": "wayfinder-monorepo", "private": true }' }, root .. "/package.json")
  vim.fn.writefile({ '{ "name": "web-app" }' }, web_root .. "/package.json")
  vim.fn.writefile({ '{ "name": "admin-app" }' }, admin_root .. "/package.json")

  vim.fn.writefile({
    "export function createUser(name) {",
    "  return { id: name.toLowerCase(), name };",
    "}",
  }, web_root .. "/src/user_service.ts")

  vim.fn.writefile({
    'import { createUser } from "../src/user_service";',
    'export const webUser = createUser("Web");',
    'export const webUserCopy = "createUser";',
  }, web_root .. "/src/user_page.ts")

  vim.fn.writefile({
    'import { createUser } from "../src/user_service";',
    'describe("createUser", () => {',
    '  it("works", () => createUser("Spec"));',
    "})",
  }, web_root .. "/tests/user_service_test.ts")

  vim.fn.writefile({
    'export const adminUserCopy = "createUser";',
    'export function createUserBanner() {',
    '  return "createUser";',
    "}",
  }, admin_root .. "/src/user_page.ts")

  vim.fn.writefile({
    'describe("admin createUser", () => {',
    '  it("mentions createUser", () => expect("createUser").toBeTruthy());',
    "})",
  }, admin_root .. "/tests/admin_user_test.ts")

  run_system({ "git", "init", "-b", "main", root })
  run_system({ "git", "-C", root, "config", "user.name", "Wayfinder Tests" })
  run_system({ "git", "-C", root, "config", "user.email", "wayfinder@example.com" })
  run_system({ "git", "-C", root, "add", "." })
  run_system({ "git", "-C", root, "commit", "-m", "fixture: monorepo" })

  return {
    root = root,
    web_root = web_root,
    admin_root = admin_root,
    web_file = web_root .. "/src/user_service.ts",
  }
end

local monorepo_fixture = make_monorepo_fixture()

-- Shared helpers -------------------------------------------------------------

local function with_setup(opts, fn)
  wayfinder.setup(opts)
  local ok, err = pcall(fn)
  wayfinder.setup({})
  if not ok then
    error(err, 0)
  end
end

local function open_typescript(path)
  vim.cmd.edit(path)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = "typescript"
  return bufnr
end

local function stop_lsp_clients(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    client:stop()
  end
end

local function start_demo_lsp(bufnr, root, opts)
  opts = opts or {}
  stop_lsp_clients(bufnr)

  vim.lsp.start({
    name = opts.name or "wayfinder-demo-lsp",
    cmd = { "python3", vim.fs.normalize(vim.fn.getcwd() .. "/demo/fake_lsp.py") },
    cmd_env = opts.cmd_env,
    root_dir = root,
  }, {
    bufnr = bufnr,
  })

  local attached = vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
  end)
  assert_ok(attached, "demo lsp did not attach")
end

-- Tests ---------------------------------------------------------------------

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
  layout.render = function() end
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

test("filter parser supports positive negated and quoted terms", function()
  -- Guards the local query parser so multi-term, negated, and quoted filters stay predictable.
  local parsed = filter_util.parse('user !test "service layer" !"git status"')
  assert_ok(vim.deep_equal(parsed.include, { "user", "service layer" }), "expected positive terms to parse")
  assert_ok(vim.deep_equal(parsed.exclude, { "test", "git status" }), "expected negated terms to parse")
end)

test("filter matcher uses and semantics with negation", function()
  -- Guards the upgraded filter matcher so include terms must all match and excluded terms remove items.
  local item = {
    label = "create user service",
    secondary = "tests/user_service_spec.ts",
    detail = "src/user_service.ts",
  }

  assert_ok(filter_util.match(item, "create user"), "expected include terms to AND together")
  assert_ok(not filter_util.match(item, "create account"), "expected missing include term to fail")
  assert_ok(not filter_util.match(item, "create !spec"), "expected negated term to exclude a match")
  assert_ok(filter_util.match(item, '"user service" !git'), "expected phrase include and unrelated negation to pass")
end)

test("tests source finds likely tests", function()
  -- Guards the heuristic test source so it keeps returning useful candidates.
  await_callback(function(done)
    return tests_source.collect({
      path = git_fixture_root .. "/src/user_service.ts",
      cwd = git_fixture_root,
      symbol = { text = "createUser" },
    }, done)
  end, function(items)
    assert_ok(#items > 0, "expected likely tests")
  end, {
    message = "tests source did not finish",
  })
end)

test("git source returns commits", function()
  -- Guards the git facet so commit rows and repo metadata continue to populate.
  await_callback(function(done)
    return git_source.collect({
      path = git_fixture_root .. "/src/user_service.ts",
      cwd = git_fixture_root,
    }, done)
  end, function(items)
    assert_ok(#items > 0, "expected git commits")
    assert_ok(items[1].git and items[1].git.repo_root, "expected git repo metadata")
  end, {
    message = "git source did not finish",
  })
end)

test("lsp source returns definitions references and callers", function()
  -- Guards the happy-path LSP flow across Calls and Refs.
  local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
  start_demo_lsp(bufnr, fixture_root)
  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  await_callback(function(done)
    return lsp_source.collect({
      bufnr = bufnr,
      path = fixture_root .. "/src/user_service.ts",
      cwd = fixture_root,
      filetype = "typescript",
      symbol = { text = "createUser" },
    }, done)
  end, function(items)
    local facets = {}
    for _, item in ipairs(items) do
      facets[item.facet] = true
    end
    assert_ok(#items >= 4, "expected lsp results")
    assert_ok(facets.calls, "expected calls facet results")
    assert_ok(facets.refs, "expected refs facet results")
  end, {
    message = "lsp source did not finish",
  })
end)

test("lsp source falls back to grep references without lsp", function()
  -- Guards text-match fallback when no LSP client is attached.
  local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
  stop_lsp_clients(bufnr)
  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  await_callback(function(done)
    return lsp_source.collect({
      bufnr = bufnr,
      path = fixture_root .. "/src/user_service.ts",
      cwd = fixture_root,
      filetype = "typescript",
      symbol = { text = "createUser" },
    }, done)
  end, function(items)
    local grep_refs = vim.tbl_filter(function(item)
      return item.facet == "refs" and item.source == "grep"
    end, items)
    assert_ok(#grep_refs > 0, "expected grep fallback references")
  end, {
    message = "grep fallback did not finish",
  })
end)

test("lsp source cancel ignores stale responses", function()
  -- Guards stale-request cancellation so closed or replaced sessions do not get late LSP mutations.
  local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
  start_demo_lsp(bufnr, fixture_root, {
    name = "wayfinder-demo-lsp-delayed-cancel",
    cmd_env = { WAYFINDER_LSP_DELAY_MS = "200" },
  })

  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  local called = false
  local handle = lsp_source.collect({
    bufnr = bufnr,
    path = fixture_root .. "/src/user_service.ts",
    cwd = fixture_root,
    project_root = fixture_root,
    filetype = "typescript",
    symbol = { text = "createUser" },
  }, function()
    called = true
  end)

  assert_ok(handle and handle.cancel, "expected cancel handle")
  handle.cancel()
  vim.wait(600, function()
    return called
  end)
  assert_ok(not called, "canceled lsp collection should not invoke callback")
end)

test("lsp source timeout finalizes without hanging", function()
  -- Guards slow LSP behavior so refs time out cleanly instead of leaving collection stuck.
  with_setup({
    limits = {
      refs = { max_results = 200, timeout_ms = 80 },
    },
  }, function()
    local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
    start_demo_lsp(bufnr, fixture_root, {
      name = "wayfinder-demo-lsp-delayed-timeout",
      cmd_env = { WAYFINDER_LSP_DELAY_MS = "200" },
    })

    vim.api.nvim_win_set_cursor(0, { 1, 18 })

    local started = vim.uv.now()
    await_callback(function(done)
      return lsp_source.collect({
        bufnr = bufnr,
        path = fixture_root .. "/src/user_service.ts",
        cwd = fixture_root,
        project_root = fixture_root,
        filetype = "typescript",
        symbol = { text = "createUser" },
      }, done)
    end, function(items)
      assert_ok(type(items) == "table", "expected timeout to finalize with a result table")
    end, {
      timeout_ms = 1000,
      message = "timed lsp collection did not finish",
    })
    local elapsed = vim.uv.now() - started
    assert_ok(elapsed < 500, "timed lsp collection should finalize promptly")
  end)
end)

test("package scope limits grep references to the nearest package", function()
  -- Guards package scope for grep fallback so broad text matches stay inside the nearest app/module.
  with_setup({
    scope = { mode = "package" },
    limits = {
      refs = { max_results = 50 },
      text = { enabled = true, max_results = 2, timeout_ms = 800 },
    },
  }, function()
    local resolved_scope = scope_util.resolve(monorepo_fixture.web_file, monorepo_fixture.root)
    vim.cmd.enew()
    local scratch = vim.api.nvim_get_current_buf()
    vim.bo[scratch].filetype = "typescript"

    await_callback(function(done)
      return lsp_source.collect({
        bufnr = scratch,
        path = monorepo_fixture.web_file,
        cwd = monorepo_fixture.root,
        project_root = monorepo_fixture.root,
        scope_root = resolved_scope.root,
        filetype = "typescript",
        symbol = { text = "createUser" },
      }, done)
    end, function(items)
      local grep_refs = vim.tbl_filter(function(item)
        return item.facet == "refs" and item.source == "grep"
      end, items)
      assert_ok(#grep_refs == 2, "expected text-match limit to apply")
      for _, item in ipairs(grep_refs) do
        assert_ok(vim.startswith(item.path, monorepo_fixture.web_root .. "/"), "expected package-scoped text match")
        assert_ok(not vim.startswith(item.path, monorepo_fixture.admin_root .. "/"), "expected admin package to be excluded")
      end
    end, {
      message = "package-scoped grep fallback did not finish",
    })
  end)
end)

test("tests and git sources respect package scope and source limits", function()
  -- Guards package scope and per-source caps for non-LSP sources in monorepo-style layouts.
  with_setup({
    scope = { mode = "package" },
    limits = {
      tests = { max_results = 5, timeout_ms = 800 },
      git = { enabled = true, max_commits = 1, timeout_ms = 400 },
    },
  }, function()
    local resolved_scope = scope_util.resolve(monorepo_fixture.web_file, monorepo_fixture.root)

    await_callback(function(done)
      return tests_source.collect({
        path = monorepo_fixture.web_file,
        cwd = monorepo_fixture.root,
        project_root = monorepo_fixture.root,
        scope_root = resolved_scope.root,
        symbol = { text = "createUser" },
      }, done)
    end, function(items)
      assert_ok(#items > 0, "expected package-scoped tests")
      for _, item in ipairs(items) do
        assert_ok(vim.startswith(item.path, monorepo_fixture.web_root .. "/"), "expected tests to stay inside package scope")
      end
    end, {
      message = "tests source did not finish",
    })

    await_callback(function(done)
      return git_source.collect({
        path = git_fixture_root .. "/src/user_service.ts",
        cwd = git_fixture_root,
        project_root = git_fixture_root,
        scope_root = git_fixture_root,
      }, done)
    end, function(items)
      assert_ok(#items == 1, "expected git commit limit to apply")
    end, {
      message = "git source did not finish",
    })
  end)
end)

if #failures > 0 then
  print("")
  print(string.format("%d test(s) failed", #failures))
  vim.cmd.cquit(1)
else
  print("")
  print("13 test(s) passed")
end
