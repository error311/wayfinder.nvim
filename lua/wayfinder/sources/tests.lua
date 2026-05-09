local async = require("wayfinder.util.async")
local config = require("wayfinder.config")
local items = require("wayfinder.util.items")
local paths = require("wayfinder.util.paths")
local text = require("wayfinder.util.text")

local M = {}

local function file_candidates(ctx, done)
  local root = ctx.scope_root or ctx.project_root or ctx.cwd
  local test_limits = config.values.limits.tests

  async.system({ "git", "ls-files", "--", "." }, {
    cwd = root,
    timeout_ms = test_limits.timeout_ms,
  }, function(result)
    if result.code == 0 and not result.timed_out then
      local lines = vim.split(result.stdout or "", "\n", { trimempty = true })
      done(vim.tbl_map(function(path)
        return paths.normalize(root .. "/" .. path)
      end, lines))
      return
    end

    done(vim.fs.find(function(name)
      return name:match("%.lua$")
        or name:match("%.ts$")
        or name:match("%.tsx$")
        or name:match("%.js$")
    end, {
      path = root,
      type = "file",
      limit = math.max(test_limits.max_results * 12, 300),
    }))
  end)
end

local function score(path, ctx)
  local score_value = 0
  local basename = paths.basename(ctx.path or ""):gsub("%..+$", "")
  local lower = path:lower()
  local symbol = ctx.symbol and ctx.symbol.text:lower() or nil
  local reasons = {}

  if lower:match("test") or lower:match("spec") then
    score_value = score_value + 40
    reasons[#reasons + 1] = "test/spec file"
  end
  if basename ~= "" and lower:find(basename:lower(), 1, true) then
    score_value = score_value + 35
    reasons[#reasons + 1] = "filename match"
  end
  if symbol and lower:find(symbol, 1, true) then
    score_value = score_value + 20
    reasons[#reasons + 1] = "symbol text match"
  end
  if lower:find("__tests__", 1, true) or lower:find("/tests/", 1, true) then
    score_value = score_value + 10
    reasons[#reasons + 1] = "tests directory"
  end

  return score_value, reasons
end

local function line_has_test_keyword(line)
  return line:find("describe%s*%(", 1)
    or line:find("it%s*%(", 1)
    or line:find("test%s*%(", 1)
    or line:find("def%s+test_", 1)
    or line:find("function%s+test_", 1)
end

local function target_line(path, ctx)
  local ok, lines = pcall(vim.fn.readfile, path, "", 250)
  if not ok or #lines == 0 then
    return 1, paths.basename(path), "heuristic match"
  end

  local symbol = ctx.symbol and ctx.symbol.text and ctx.symbol.text:lower() or nil
  local basename = paths.basename(ctx.path or ""):gsub("%..+$", ""):lower()
  local best = nil
  local first_nonempty = nil

  for lnum, raw in ipairs(lines) do
    local line = text.one_line(raw)
    if line ~= "" and not first_nonempty then
      first_nonempty = { lnum = lnum, col = 1, label = line, reason = "test file" }
    end

    local lower = line:lower()
    local score_value = 0
    local reason = nil
    local target_col = 1
    local test_keyword_col = line_has_test_keyword(line)

    local symbol_col = symbol and lower:find(symbol, 1, true) or nil
    if symbol_col then
      score_value = score_value + 60
      reason = test_keyword_col and "symbol test block" or "symbol text match"
      target_col = symbol_col
    end
    local basename_col = basename ~= "" and lower:find(basename, 1, true) or nil
    if basename_col then
      score_value = score_value + 25
      reason = reason or "filename text match"
      target_col = target_col == 1 and basename_col or target_col
    end
    if test_keyword_col then
      score_value = score_value + 35
      reason = reason or "test block"
      target_col = target_col == 1 and test_keyword_col or target_col
    end

    if score_value > 0 and (not best or score_value > best.score) then
      best = {
        score = score_value,
        lnum = lnum,
        col = target_col,
        label = line,
        reason = reason or "heuristic match",
      }
    end
  end

  local picked = best
    or first_nonempty
    or { lnum = 1, label = paths.basename(path), reason = "test file" }
  return picked.lnum, picked.col or 1, picked.label, picked.reason
end

function M.collect(ctx, callback)
  file_candidates(ctx, function(candidates)
    local results = {}
    local limit = config.values.limits.tests.max_results

    for _, path in ipairs(candidates) do
      if path ~= ctx.path then
        local score_value, reasons = score(path, ctx)
        if score_value > 0 then
          local lnum, col, label, target_reason = target_line(path, ctx)
          table.insert(results, {
            id = items.item_id({ "test", path }),
            facet = "tests",
            kind = "test",
            label = label,
            path = path,
            lnum = lnum,
            col = col,
            preview_range = { start = lnum, ["end"] = lnum + 8 },
            source = "test",
            score = 10 + math.floor(score_value / 2),
            badge = "TEST",
            detail = paths.display(path, ctx.project_root),
            secondary = paths.display(path, ctx.project_root),
            reason = target_reason or reasons[1] or "heuristic match",
            group = "Likely Tests",
            icon = config.values.icons.tests,
          })
        end
      end
    end

    table.sort(results, items.score_sort)
    if #results > limit then
      local limited = {}
      for index = 1, limit do
        limited[index] = results[index]
      end
      callback(limited)
      return
    end

    callback(results)
  end)
end

return M
