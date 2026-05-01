local async = require("wayfinder.util.async")
local config = require("wayfinder.config")
local items = require("wayfinder.util.items")
local paths = require("wayfinder.util.paths")
local scope = require("wayfinder.util.scope")
local text = require("wayfinder.util.text")

local M = {}

local BATCH_SIZE = 40

---@param timer uv.uv_timer_t?
---@return nil
local function clear_timer(timer)
  if timer then
    timer:stop()
    timer:close()
  end
  return nil
end

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

local function active(ctx)
  return not ctx.is_stale or ctx.is_stale() == false
end

local function register_cancel(ctx, cancel)
  if cancel and ctx.track_cancel then
    ctx.track_cancel(cancel)
  end
end

local function location_item(facet, kind, badge, score, location, ctx)
  if not location then
    return nil
  end

  local uri = location.uri or location.targetUri
  local range = location.range or location.targetSelectionRange or location.targetRange
  if not uri or not range then
    return nil
  end

  local path = vim.uri_to_fname(uri)
  local lnum = range.start.line + 1
  local col = range.start.character + 1
  local label = text.line_at(path, lnum)
  if label == "" then
    return nil
  end

  return {
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
  }
end

local function post_filter(found, ctx)
  return scope.filter(found, ctx.scope_root)
end

local function process_locations(locations, mapper, ctx, opts, callback)
  opts = opts or {}
  local max_results = opts.max_results
  local out = {}
  local index = 1

  local function step()
    if not active(ctx) then
      return
    end

    local stop = math.min(index + BATCH_SIZE - 1, #locations)
    for current = index, stop do
      local item = mapper(locations[current], ctx)
      if item then
        out[#out + 1] = item
        if max_results and #out >= max_results then
          callback(out)
          return
        end
      end
    end

    if stop >= #locations then
      callback(out)
      return
    end

    index = stop + 1
    vim.schedule(step)
  end

  if #locations == 0 then
    callback(out)
    return
  end

  vim.schedule(step)
end

local function response_lists(responses)
  local lists = {}
  for _, response in pairs(responses or {}) do
    if response and response.result then
      local result = response.result
      if vim.islist(result) then
        lists[#lists + 1] = result
      else
        lists[#lists + 1] = { result }
      end
    end
  end
  return lists
end

local function process_response_locations(responses, mapper, ctx, opts, callback)
  local lists = response_lists(responses)
  local out = {}
  local max_results = opts and opts.max_results or nil
  local list_index = 1
  local item_index = 1

  local function step()
    if not active(ctx) then
      return
    end

    local processed = 0
    while list_index <= #lists do
      local list = lists[list_index]
      while item_index <= #list do
        local item = mapper(list[item_index], ctx)
        if item then
          out[#out + 1] = item
          if max_results and #out >= max_results then
            callback(out)
            return
          end
        end

        item_index = item_index + 1
        processed = processed + 1
        if processed >= BATCH_SIZE then
          vim.schedule(step)
          return
        end
      end

      list_index = list_index + 1
      item_index = 1
    end

    callback(out)
  end

  if #lists == 0 then
    callback(out)
    return
  end

  vim.schedule(step)
end

local function request_all(bufnr, method, params, ctx, callback)
  local clients = vim.tbl_filter(function(client)
    return client and client:supports_method(method, bufnr)
  end, vim.lsp.get_clients({ bufnr = bufnr }))

  if #clients == 0 then
    async.defer(function()
      callback({})
    end)
    return
  end

  local remaining = #clients
  local responses = {}

  for _, client in ipairs(clients) do
    local ok, request_id = client:request(method, params, function(err, result)
      if not active(ctx) then
        return
      end

      responses[client.id] = err and nil or { result = result }
      remaining = remaining - 1
      if remaining == 0 then
        async.defer(function()
          if active(ctx) then
            callback(responses)
          end
        end)
      end
    end, bufnr)

    if ok and request_id then
      register_cancel(ctx, function()
        pcall(client.cancel_request, client, request_id)
      end)
    else
      remaining = remaining - 1
    end
  end

  if remaining == 0 then
    async.defer(function()
      if active(ctx) then
        callback(responses)
      end
    end)
  end
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
  ---@type uv.uv_timer_t?
  local timer = nil

  local function complete()
    if finished then
      return
    end

    finished = true
    timer = clear_timer(timer)
    if job_id and job_id > 0 then
      pcall(vim.fn.jobstop, job_id)
    end

    if not active(ctx) then
      return
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
      reason = "plain text fallback",
      group = "Text Matches",
      icon = config.values.icons.refs,
    }
  end

  job_id = vim.fn.jobstart(cmd, {
    cwd = base,
    stdout_buffered = false,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if finished or not active(ctx) or not data then
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
          complete()
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
        if active(ctx) then
          callback({})
        end
        return
      end

      complete()
    end,
  })

  if job_id <= 0 then
    callback({})
    return
  end

  register_cancel(ctx, function()
    finished = true
    timer = clear_timer(timer)
    if job_id and job_id > 0 then
      pcall(vim.fn.jobstop, job_id)
    end
  end)

  if text_limits.timeout_ms and text_limits.timeout_ms > 0 then
    timer = assert(vim.uv.new_timer(), "wayfinder grep timer")
    timer:start(text_limits.timeout_ms, 0, function()
      vim.schedule(function()
        if finished then
          return
        end
        complete()
      end)
    end)
  end
end

local function gather_definitions(ctx, push)
  request_all(ctx.bufnr, "textDocument/definition", current_params(ctx.bufnr), ctx, function(responses)
    process_response_locations(responses, function(location, current_ctx)
      return location_item("calls", "definition", "DEF", 120, location, current_ctx)
    end, ctx, {}, function(found)
      if active(ctx) then
        push(found)
      end
    end)
  end)
end

local function gather_references(ctx, push)
  local refs_limit = config.values.limits.refs.max_results

  local function collect(include_declaration, done)
    ---@type lsp.ReferenceParams
    local params = vim.tbl_extend("force", current_params(ctx.bufnr), {
      context = { includeDeclaration = include_declaration },
    })

    request_all(ctx.bufnr, "textDocument/references", params, ctx, function(responses)
      process_response_locations(responses, function(location, current_ctx)
        local item = location_item("refs", "reference", "REF", 90, location, current_ctx)
        if item and current_ctx.scope_root and not scope.contains(current_ctx.scope_root, item.path) then
          return nil
        end
        return item
      end, ctx, { max_results = refs_limit }, function(found)
        if active(ctx) then
          done(found)
        end
      end)
    end)
  end

  collect(false, function(found)
    if not active(ctx) then
      return
    end

    collect(true, function(retried)
      if not active(ctx) then
        return
      end

      grep_references(ctx, function(grep_found)
        if not active(ctx) then
          return
        end

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
  request_all(ctx.bufnr, "textDocument/prepareCallHierarchy", current_params(ctx.bufnr), ctx, function(responses)
    local items_for_clients = {}
    for client_id, response in pairs(responses) do
      if response and response.result and response.result[1] then
        items_for_clients[#items_for_clients + 1] = {
          client = vim.lsp.get_client_by_id(client_id),
          item = response.result[1],
        }
      end
    end

    if #items_for_clients == 0 then
      push({})
      return
    end

    local aggregate = {}
    local remaining = #items_for_clients

    local function finish()
      remaining = remaining - 1
      if remaining == 0 and active(ctx) then
        push(aggregate)
      end
    end

    for _, entry in ipairs(items_for_clients) do
      local client = entry.client
      if not client then
        finish()
      else
        local ok, request_id = client:request("callHierarchy/incomingCalls", { item = entry.item }, function(_, result)
          if not active(ctx) then
            return
          end

          local locations = {}
          for _, call in ipairs(result or {}) do
            local from = call.from
            if from then
              locations[#locations + 1] = {
                uri = from.uri,
                range = from.selectionRange or from.range,
              }
            end
          end

          process_locations(locations, function(location, current_ctx)
            return location_item("calls", "caller", "CALL", 110, location, current_ctx)
          end, ctx, {}, function(found)
            if active(ctx) and #found > 0 then
              vim.list_extend(aggregate, found)
            end
            finish()
          end)
        end, ctx.bufnr)

        if ok and request_id then
          register_cancel(ctx, function()
            pcall(client.cancel_request, client, request_id)
          end)
        elseif not ok then
          finish()
        end
      end
    end
  end)
end

function M.collect(ctx, callback)
  if not ctx.symbol then
    callback({})
    return {
      cancel = function() end,
    }
  end

  local canceled = false
  local finished = false
  local cancelers = {}
  local results = {}
  local pending = 3
  ---@type uv.uv_timer_t?
  local timer = nil
  local refs_timeout_ms = vim.tbl_get(config.values, "limits", "refs", "timeout_ms")

  local control = vim.tbl_extend("force", ctx, {
    is_stale = function()
      return canceled or (ctx.is_stale and ctx.is_stale()) or false
    end,
    track_cancel = function(cancel)
      if cancel then
        cancelers[#cancelers + 1] = cancel
      end
    end,
  })

  local function finalize()
    if finished then
      return
    end

    finished = true
    canceled = true
    timer = clear_timer(timer)
    for _, cancel in ipairs(cancelers) do
      pcall(cancel)
    end
    callback(sorted(results))
  end

  local function push(part)
    if canceled then
      return
    end

    if part and #part > 0 then
      vim.list_extend(results, part)
    end

    pending = pending - 1
    if pending == 0 then
      finalize()
    end
  end

  gather_definitions(control, push)
  vim.defer_fn(function()
    if not canceled then
      gather_callers(control, push)
    end
  end, 10)
  vim.defer_fn(function()
    if not canceled then
      gather_references(control, push)
    end
  end, 20)

  if refs_timeout_ms and refs_timeout_ms > 0 then
    timer = assert(vim.uv.new_timer(), "wayfinder refs timer")
    timer:start(refs_timeout_ms, 0, function()
      vim.schedule(function()
        finalize()
      end)
    end)
  end

  return {
    cancel = function()
      if finished then
        return
      end

      finished = true
      canceled = true
      timer = clear_timer(timer)
      for _, cancel in ipairs(cancelers) do
        pcall(cancel)
      end
    end,
  }
end

return M
