vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.swapfile = false
package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. package.path

---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function() end

local M = {}

M.wayfinder = require("wayfinder")
M.actions = require("wayfinder.actions")
M.state = require("wayfinder.state")
M.layout = require("wayfinder.layout")
M.trail = require("wayfinder.trail")
M.trail_persistence = require("wayfinder.trail_persistence")
M.trail_store = require("wayfinder.trail_store")
M.lsp_source = require("wayfinder.sources.lsp")
M.tests_source = require("wayfinder.sources.tests")
M.git_source = require("wayfinder.sources.git")
M.filter_util = require("wayfinder.util.filter")
M.scope_util = require("wayfinder.util.scope")

M.wayfinder.setup()

M.failures = {}
M.test_count = 0

function M.test(name, fn)
  M.test_count = M.test_count + 1
  local ok, err = pcall(fn)
  if ok then
    print("ok   " .. name)
  else
    print("FAIL " .. name)
    print(err)
    table.insert(M.failures, name)
  end
end

function M.assert_ok(value, message)
  if not value then
    error(message or "assertion failed", 0)
  end
end

function M.await(predicate, timeout_ms, message)
  local finished = vim.wait(timeout_ms or 2000, predicate)
  M.assert_ok(finished, message or "timed out waiting for async work")
end

function M.await_callback(start, validate, opts)
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

  M.await(function()
    return done
  end, opts.timeout_ms, opts.message)

  if callback_err then
    error(callback_err, 0)
  end

  return result, handle
end

M.fixture_root = vim.fs.normalize(vim.fn.getcwd() .. "/demo/fixture-app")

function M.run_system(args, cwd)
  vim.fn.system(args, cwd)
  M.assert_ok(vim.v.shell_error == 0, "command failed: " .. table.concat(args, " "))
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

  M.run_system({ "git", "init", "-b", "main", root })
  M.run_system({ "git", "-C", root, "config", "user.name", "Wayfinder Tests" })
  M.run_system({ "git", "-C", root, "config", "user.email", "wayfinder@example.com" })
  M.run_system({ "git", "-C", root, "add", "." })
  M.run_system({ "git", "-C", root, "commit", "-m", "fixture: initial" })

  vim.fn.writefile({
    "export function createUser(name) {",
    "  return { id: name.toLowerCase(), name };",
    "}",
    "",
    'export const USER_ACTION = "createUser";',
    'export const USER_COPY = "createUser helps bootstrap demos.";',
  }, root .. "/src/user_service.ts")

  M.run_system({ "git", "-C", root, "add", "src/user_service.ts" })
  M.run_system({ "git", "-C", root, "commit", "-m", "fixture: add fallback copy" })

  return root
end

M.git_fixture_root = make_git_fixture()

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

  M.run_system({ "git", "init", "-b", "main", root })
  M.run_system({ "git", "-C", root, "config", "user.name", "Wayfinder Tests" })
  M.run_system({ "git", "-C", root, "config", "user.email", "wayfinder@example.com" })
  M.run_system({ "git", "-C", root, "add", "." })
  M.run_system({ "git", "-C", root, "commit", "-m", "fixture: monorepo" })

  return {
    root = root,
    web_root = web_root,
    admin_root = admin_root,
    web_file = web_root .. "/src/user_service.ts",
  }
end

M.monorepo_fixture = make_monorepo_fixture()

function M.with_setup(opts, fn)
  M.wayfinder.setup(opts)
  local ok, err = pcall(fn)
  M.wayfinder.setup({})
  if not ok then
    error(err, 0)
  end
end

function M.open_typescript(path)
  vim.cmd.edit(path)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = "typescript"
  return bufnr
end

function M.stop_lsp_clients(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    client:stop()
  end
end

function M.start_demo_lsp(bufnr, root, opts)
  opts = opts or {}
  M.stop_lsp_clients(bufnr)

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
  M.assert_ok(attached, "demo lsp did not attach")
end

function M.finish()
  if #M.failures > 0 then
    print("")
    print(string.format("%d test(s) failed", #M.failures))
    vim.cmd.cquit(1)
    return
  end

  print("")
  print(string.format("%d test(s) passed", M.test_count))
end

package.loaded["support"] = M

return M
