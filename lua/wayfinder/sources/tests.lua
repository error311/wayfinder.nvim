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
      return name:match("%.lua$") or name:match("%.ts$") or name:match("%.tsx$") or name:match("%.js$")
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

  if lower:match("test") or lower:match("spec") then
    score_value = score_value + 40
  end
  if basename ~= "" and lower:find(basename:lower(), 1, true) then
    score_value = score_value + 35
  end
  if symbol and lower:find(symbol, 1, true) then
    score_value = score_value + 20
  end
  if lower:find("__tests__", 1, true) or lower:find("/tests/", 1, true) then
    score_value = score_value + 10
  end

  return score_value
end

function M.collect(ctx, callback)
  file_candidates(ctx, function(candidates)
    local results = {}
    local limit = config.values.limits.tests.max_results

    for _, path in ipairs(candidates) do
      if path ~= ctx.path then
        local score_value = score(path, ctx)
        if score_value > 0 then
          table.insert(results, {
            id = items.item_id({ "test", path }),
            facet = "tests",
            kind = "test",
            label = text.line_at(path, 1) ~= "" and text.line_at(path, 1) or paths.basename(path),
            path = path,
            lnum = 1,
            col = 1,
            preview_range = { start = 1, ["end"] = 8 },
            source = "test",
            score = 10 + math.floor(score_value / 2),
            badge = "TEST",
            detail = paths.display(path, ctx.project_root),
            secondary = paths.display(path, ctx.project_root),
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
