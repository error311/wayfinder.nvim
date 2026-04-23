vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.swapfile = false
vim.notify = function() end

local wayfinder = require("wayfinder")
local trail = require("wayfinder.trail")
local lsp_source = require("wayfinder.sources.lsp")
local tests_source = require("wayfinder.sources.tests")
local git_source = require("wayfinder.sources.git")

wayfinder.setup()

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
    'export const USER_COPY = "createUser helps bootstrap demos.";'
  }, root .. "/src/user_service.ts")

  run_system({ "git", "-C", root, "add", "src/user_service.ts" })
  run_system({ "git", "-C", root, "commit", "-m", "fixture: add fallback copy" })

  return root
end

local git_fixture_root = make_git_fixture()

test("trail pins and removes items", function()
  trail.clear()
  assert_ok(trail.pin({ id = "one", label = "one" }), "pin should succeed")
  assert_ok(trail.has("one"), "trail should contain item")
  assert_ok(trail.remove("one"), "remove should succeed")
end)

test("tests source finds likely tests", function()
  local done = false
  local callback_err = nil
  tests_source.collect({
    path = git_fixture_root .. "/src/user_service.ts",
    cwd = git_fixture_root,
    symbol = { text = "createUser" },
  }, function(items)
    local ok, err = pcall(function()
      assert_ok(#items > 0, "expected likely tests")
    end)
    callback_err = err
    done = true
  end)
  vim.wait(2000, function()
    return done
  end)
  assert_ok(done, "tests source did not finish")
  if callback_err then
    error(callback_err, 0)
  end
end)

test("git source returns commits", function()
  local done = false
  local callback_err = nil
  git_source.collect({
    path = git_fixture_root .. "/src/user_service.ts",
    cwd = git_fixture_root,
  }, function(items)
    local ok, err = pcall(function()
      assert_ok(#items > 0, "expected git commits")
      assert_ok(items[1].git and items[1].git.repo_root, "expected git repo metadata")
    end)
    callback_err = err
    done = true
  end)
  vim.wait(2000, function()
    return done
  end)
  assert_ok(done, "git source did not finish")
  if callback_err then
    error(callback_err, 0)
  end
end)

test("lsp source returns definitions references and callers", function()
  vim.cmd.edit(fixture_root .. "/src/user_service.ts")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = "typescript"

  vim.lsp.start({
    name = "wayfinder-demo-lsp",
    cmd = { "python3", vim.fs.normalize(vim.fn.getcwd() .. "/demo/fake_lsp.py") },
    root_dir = fixture_root,
  }, {
    bufnr = bufnr,
  })

  local attached = vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
  end)
  assert_ok(attached, "demo lsp did not attach")

  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  local done = false
  local callback_err = nil
  lsp_source.collect({
    bufnr = bufnr,
    path = fixture_root .. "/src/user_service.ts",
    cwd = fixture_root,
    filetype = "typescript",
    symbol = { text = "createUser" },
  }, function(items)
    local ok, err = pcall(function()
      local facets = {}
      for _, item in ipairs(items) do
        facets[item.facet] = true
      end
      assert_ok(#items >= 4, "expected lsp results")
      assert_ok(facets.calls, "expected calls facet results")
      assert_ok(facets.refs, "expected refs facet results")
    end)
    callback_err = err
    done = true
  end)

  vim.wait(2000, function()
    return done
  end)
  assert_ok(done, "lsp source did not finish")
  if callback_err then
    error(callback_err, 0)
  end
end)

test("lsp source falls back to grep references without lsp", function()
  vim.cmd.edit(fixture_root .. "/src/user_service.ts")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = "typescript"
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    client:stop()
  end

  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  local done = false
  local callback_err = nil
  lsp_source.collect({
    bufnr = bufnr,
    path = fixture_root .. "/src/user_service.ts",
    cwd = fixture_root,
    filetype = "typescript",
    symbol = { text = "createUser" },
  }, function(items)
    local ok, err = pcall(function()
      local grep_refs = vim.tbl_filter(function(item)
        return item.facet == "refs" and item.source == "grep"
      end, items)
      assert_ok(#grep_refs > 0, "expected grep fallback references")
    end)
    callback_err = err
    done = true
  end)

  vim.wait(2000, function()
    return done
  end)
  assert_ok(done, "grep fallback did not finish")
  if callback_err then
    error(callback_err, 0)
  end
end)

if #failures > 0 then
  print("")
  print(string.format("%d test(s) failed", #failures))
  vim.cmd.cquit(1)
else
  print("")
  print("5 test(s) passed")
end
