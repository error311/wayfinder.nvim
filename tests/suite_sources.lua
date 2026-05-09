local t = require("support")

local test = t.test
local assert_ok = t.assert_ok
local await_callback = t.await_callback
local with_setup = t.with_setup
local open_typescript = t.open_typescript
local start_demo_lsp = t.start_demo_lsp
local stop_lsp_clients = t.stop_lsp_clients
local fixture_root = t.fixture_root
local git_fixture_root = t.git_fixture_root
local monorepo_fixture = t.monorepo_fixture
local lsp_source = t.lsp_source
local tests_source = t.tests_source
local git_source = t.git_source
local scope_util = t.scope_util

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
    assert_ok(
      type(items[1].reason) == "string" and items[1].reason ~= "",
      "expected test match reason"
    )
    assert_ok(items[1].lnum > 1, "expected likely test to target a relevant test block")
    assert_ok(items[1].col > 1, "expected likely test to target the matched symbol column")
    assert_ok(
      items[1].label:find("createUser", 1, true) ~= nil,
      "expected likely test label to show the matched test context"
    )
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
    assert_ok(items[1].reason == "recent commit touching current file", "expected git reason")
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

test("lsp source reports partial results before finalizing", function()
  -- Guards progressive loading so useful LSP rows can render before the slowest LSP path completes.
  local bufnr = open_typescript(fixture_root .. "/src/user_service.ts")
  start_demo_lsp(bufnr, fixture_root)
  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  local partials = {}
  await_callback(function(done)
    return lsp_source.collect({
      bufnr = bufnr,
      path = fixture_root .. "/src/user_service.ts",
      cwd = fixture_root,
      filetype = "typescript",
      symbol = { text = "createUser" },
      on_partial = function(items)
        partials[#partials + 1] = items
      end,
    }, done)
  end, function(items)
    assert_ok(#items >= 4, "expected final lsp results")
    assert_ok(#partials > 0, "expected at least one partial lsp update")
    assert_ok(#partials[1] <= #items, "partial results should not exceed final result count")
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
    assert_ok(grep_refs[1].reason == "plain text fallback", "expected grep fallback reason")
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
        assert_ok(
          vim.startswith(item.path, monorepo_fixture.web_root .. "/"),
          "expected package-scoped text match"
        )
        assert_ok(
          not vim.startswith(item.path, monorepo_fixture.admin_root .. "/"),
          "expected admin package to be excluded"
        )
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
        assert_ok(
          vim.startswith(item.path, monorepo_fixture.web_root .. "/"),
          "expected tests to stay inside package scope"
        )
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
