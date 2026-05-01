local async = require("wayfinder.util.async")
local items = require("wayfinder.util.items")
local paths = require("wayfinder.util.paths")

local M = {}

local config = require("wayfinder.config")

local function resolve_repo(ctx, callback)
  async.system({ "git", "rev-parse", "--show-toplevel" }, {
    cwd = ctx.scope_root or ctx.project_root or ctx.cwd,
    timeout_ms = config.values.limits.git.timeout_ms,
  }, function(result)
    if result.code ~= 0 then
      callback(nil, nil)
      return
    end

    local repo_root = vim.trim(result.stdout or "")
    if repo_root == "" then
      callback(nil, nil)
      return
    end

    callback(repo_root, paths.relative_to(repo_root, ctx.path) or ctx.path)
  end)
end

function M.collect(ctx, callback)
  local git_limits = config.values.limits.git
  if not git_limits.enabled or not ctx.path then
    callback({})
    return
  end

  resolve_repo(ctx, function(repo_root, relative)
    if not repo_root or not relative then
      callback({})
      return
    end

    async.system({
      "git",
      "log",
      "-n",
      tostring(git_limits.max_commits),
      "--pretty=format:%h%x09%s%x09%cr",
      "--",
      relative,
    }, { cwd = repo_root, timeout_ms = git_limits.timeout_ms }, function(result)
      if result.timed_out or result.code ~= 0 then
        callback({})
        return
      end

      local output = vim.split(result.stdout or "", "\n", { trimempty = true })
      local rows = {}
      for index, line in ipairs(output) do
        local hash, subject, when = line:match("^([^\t]+)\t([^\t]+)\t(.+)$")
        if hash and subject then
          table.insert(rows, {
            id = items.item_id({ "git", hash, relative }),
            facet = "git",
            kind = "commit",
            label = subject,
            path = ctx.path,
            lnum = 1,
            col = 1,
            preview_range = { start = 1, ["end"] = 10 },
            source = "git",
            score = 2 - index,
            badge = "GIT",
            detail = hash .. " • " .. when,
            secondary = paths.display(ctx.path, ctx.project_root),
            reason = "recent commit touching current file",
            group = "Recent Commits",
            icon = config.values.icons.git,
            git = {
              hash = hash,
              relative = relative,
              repo_root = repo_root,
            },
          })
        end
      end

      callback(rows)
    end)
  end)
end

return M
