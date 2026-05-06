local t = require("support")

local test = t.test
local assert_ok = t.assert_ok
local filter_util = t.filter_util

test("filter parser supports positive negated and quoted terms", function()
  -- Guards the local query parser so multi-term, negated, and quoted filters stay predictable.
  local parsed = filter_util.parse('user !test "service layer" !"git status"')
  assert_ok(
    vim.deep_equal(parsed.include, { "user", "service layer" }),
    "expected positive terms to parse"
  )
  assert_ok(
    vim.deep_equal(parsed.exclude, { "test", "git status" }),
    "expected negated terms to parse"
  )
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
  assert_ok(
    filter_util.match(item, '"user service" !git'),
    "expected phrase include and unrelated negation to pass"
  )
end)
