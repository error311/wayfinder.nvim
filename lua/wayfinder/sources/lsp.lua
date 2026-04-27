local async = require("wayfinder.util.async")
local config = require("wayfinder.config")
local items = require("wayfinder.util.items")
local paths = require("wayfinder.util.paths")
local scope = require("wayfinder.util.scope")
local text = require("wayfinder.util.text")

local M = {}

local function location_key(item)
  return table.concat({
    item.facet or "",
    item.path or "",
    item.lnum or 0,
    item.col or 0,
  }, "::")
end

local function dedupe(found)
  local seen = {}
  local out = {}

  for _, item in ipairs(found or {}) do
    local key = item and location_key(item) or nil
    if item and key and not seen[key] then
      seen[key] = true
      out[#out + 1] = item
    end
  end

  return out
end

local function sorted(found)
  local out = dedupe(found)
  table.sort(out, items.score_sort)
  return out
end

local function take(found, max_results)
  if not max_results or max_results < 1 or #found <= max_results then
    return found
  end

  local out = {}
  for index = 1, max_results do
    out[index] = found[index]
  end
  return out
end

local function current_params(bufnr)
  local client = vim.lsp.get_clients({ bufnr = bufnr })[1]
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    winid = vim.api.nvim_get_current_win()
  end
  return vim.lsp.util.make_position_params(winid, client and client.offset_encoding or "utf-16")
end

local function location_items(facet, kind, badge, score, result, ctx)
  local out = {}
  local locations = vim.islist(result) and result or { result }

  for _, location in ipairs(locations) do
    if location then
      local uri = location.uri or location.targetUri
      local range = location.range or location.targetSelectionRange or location.targetRange
      if uri and range then
        local path = vim.uri_to_fname(uri)
        local lnum = range.start.line + 1
        local col = range.start.character + 1
        local label = text.line_at(path, lnum)
        if label ~= "" then
          table.insert(out, {
            id = items.item_id({ kind, path, lnum, col }),
            facet = facet,
            kind = kind,
            label = label,
            path = path,
            lnum = lnum,
            col = col,
            preview_range = {
              start = lnum,
              ["end"] = math.max(lnum + 2, lnum),
            },
            source = "lsp",
            score = score,
            badge = badge,
            detail = paths.display(path, ctx.project_root),
            secondary = paths.display(path, ctx.project_root),
            group = facet == "calls" and (kind == "definition" and "Definitions" or "Callers") or "LSP References",
            icon = facet == "calls"
              and (kind == "definition" and config.values.icons.definition or config.values.icons.caller)
              or config.values.icons.reference,
          })
        end
      end
    end
  end

  return out
end

local function post_filter(found, ctx)
  return scope.filter(found, ctx.scope_root)
end

local function grep_references(ctx, callback)
  local text_limits = config.values.limits.text
  if not text_limits.enabled or not ctx.symbol or ctx.symbol.text == "" or vim.fn.executable("rg") ~= 1 then
    callback({})
    return
  end

  local current_line = nil
  local winid = vim.fn.bufwinid(ctx.bufnr)
  if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
    current_line = vim.api.nvim_win_get_cursor(winid)[1]
  end

  local base = ctx.scope_root or ctx.project_root or ctx.cwd
  local cmd = {
    "rg",
    "--line-number",
    "--column",
    "--no-heading",
    "--fixed-strings",
    "--word-regexp",
    ctx.symbol.text,
    ".",
  }

  local finished = false
  local collected = {}
  local pending = ""
  local job_id = nil
  local timer = nil

  local function finish()
    if finished then
      return
    end

    finished = true
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    if job_id and job_id > 0 then
      pcall(vim.fn.jobstop, job_id)
    end

    callback(take(sorted(post_filter(collected, ctx)), text_limits.max_results))
  end

  local function push_line(line)
    if line == "" or #collected >= text_limits.max_results then
      return
    end

    local relative, row, col = line:match("^([^:]+):(%d+):(%d+):")
    if not relative or not row or not col then
      return
    end

    local path = paths.normalize(base .. "/" .. relative)
    local lnum = tonumber(row)
    local cnum = tonumber(col)
    if not path or not lnum or not cnum or (path == ctx.path and current_line and lnum == current_line) then
      return
    end

    local label = text.line_at(path, lnum)
    if label == "" then
      return
    end

    collected[#collected + 1] = {
      id = items.item_id({ "grep-reference", path, lnum, cnum }),
      facet = "refs",
      kind = "reference",
      label = label,
      path = path,
      lnum = lnum,
      col = cnum,
      preview_range = {
        start = lnum,
        ["end"] = math.max(lnum + 2, lnum),
      },
      source = "grep",
      score = 70,
      badge = "TXT",
      detail = paths.display(path, ctx.project_root),
      secondary = paths.display(path, ctx.project_root),
      group = "Text Matches",
      icon = config.values.icons.refs,
    }
  end

  job_id = vim.fn.jobstart(cmd, {
    cwd = base,
    stdout_buffered = false,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if finished or not data then
        return
      end

      local lines = vim.deepcopy(data)
      if #lines == 0 then
        return
      end

      lines[1] = pending .. (lines[1] or "")
      pending = table.remove(lines) or ""

      for _, line in ipairs(lines) do
        push_line(line)
        if #collected >= text_limits.max_results then
          finish()
          return
        end
      end
    end,
    on_exit = function(_, code)
      if finished then
        return
      end

      if pending ~= "" then
        push_line(pending)
        pending = ""
      end

      if code ~= 0 and #collected == 0 then
        callback({})
        return
      end

      finish()
    end,
  })

  if job_id <= 0 then
    callback({})
    return
  end

  if text_limits.timeout_ms and text_limits.timeout_ms > 0 then
    timer = vim.uv.new_timer()
    timer:start(text_limits.timeout_ms, 0, function()
      vim.schedule(function()
        if finished then
          return
        end
        finished = true
        if timer then
          timer:stop()
          timer:close()
          timer = nil
        end
        if job_id and job_id > 0 then
          pcall(vim.fn.jobstop, job_id)
        end
        callback(take(sorted(post_filter(collected, ctx)), text_limits.max_results))
      end)
    end)
  end
end

local function flatten_responses(mapper, responses, ctx)
  local out = {}
  for _, response in pairs(responses or {}) do
    if response and response.result then
      local items_for_client = mapper(response.result, ctx)
      vim.list_extend(out, items_for_client)
    end
  end
  return out
end

local function request_all(bufnr, method, params, callback)
  if #vim.lsp.get_clients({ bufnr = bufnr }) == 0 then
    async.defer(function()
      callback({})
    end)
    return
  end

  vim.lsp.buf_request_all(bufnr, method, params, function(responses)
    async.defer(function()
      callback(responses or {})
    end)
  end)
end

local function gather_definitions(ctx, push)
  request_all(ctx.bufnr, "textDocument/definition", current_params(ctx.bufnr), function(responses)
    push(flatten_responses(function(result, c)
      return location_items("calls", "definition", "DEF", 120, result, c)
    end, responses, ctx))
  end)
end

local function gather_references(ctx, push)
  local function collect(include_declaration, done)
    local params = current_params(ctx.bufnr)
    params.context = { includeDeclaration = include_declaration }

    request_all(ctx.bufnr, "textDocument/references", params, function(responses)
      done(post_filter(flatten_responses(function(result, c)
        return location_items("refs", "reference", "REF", 90, result, c)
      end, responses, ctx), ctx))
    end)
  end

  collect(false, function(found)
    collect(true, function(retried)
      grep_references(ctx, function(grep_found)
        local refs_limit = config.values.limits.refs.max_results
        local merged = take(sorted(vim.list_extend(vim.list_extend({}, found), retried)), refs_limit)
        if #merged > 0 then
          push(sorted(vim.list_extend(merged, grep_found)))
          return
        end

        push(grep_found)
      end)
    end)
  end)
end

local function gather_callers(ctx, push)
  request_all(ctx.bufnr, "textDocument/prepareCallHierarchy", current_params(ctx.bufnr), function(responses)
    local pending = 0
    local aggregate = {}

    local function flush()
      if pending == 0 then
        push(aggregate)
      end
    end

    for client_id, response in pairs(responses) do
      local items_for_client = response and response.result
      if items_for_client and items_for_client[1] then
        pending = pending + 1
        local client = vim.lsp.get_client_by_id(client_id)
        client:request("callHierarchy/incomingCalls", { item = items_for_client[1] }, function(_, result)
          if result then
            for _, call in ipairs(result) do
              local from = call.from
              if from then
                vim.list_extend(aggregate, location_items("calls", "caller", "CALL", 110, {
                  {
                    uri = from.uri,
                    range = from.selectionRange or from.range,
                  },
                }, ctx))
              end
            end
          end
          pending = pending - 1
          flush()
        end, ctx.bufnr)
      end
    end

    flush()
  end)
end

function M.collect(ctx, callback)
  if not ctx.symbol then
    callback({})
    return
  end

  local results = {}
  local pending = 3

  local function push(part)
    if part and #part > 0 then
      vim.list_extend(results, part)
    end
    pending = pending - 1
    if pending == 0 then
      callback(sorted(results))
    end
  end

  gather_definitions(ctx, push)
  gather_callers(ctx, push)
  gather_references(ctx, push)
end

return M
