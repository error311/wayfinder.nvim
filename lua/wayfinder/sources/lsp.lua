local async = require("wayfinder.util.async")
local config = require("wayfinder.config")
local items = require("wayfinder.util.items")
local paths = require("wayfinder.util.paths")
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
            detail = paths.display(path, ctx.cwd),
            secondary = paths.display(path, ctx.cwd),
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

local function grep_references(ctx, callback)
  if not ctx.symbol or ctx.symbol.text == "" or vim.fn.executable("rg") ~= 1 then
    callback({})
    return
  end

  local current_line = nil
  local winid = vim.fn.bufwinid(ctx.bufnr)
  if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
    current_line = vim.api.nvim_win_get_cursor(winid)[1]
  end

  vim.system({
    "rg",
    "--line-number",
    "--column",
    "--no-heading",
    "--fixed-strings",
    "--word-regexp",
    ctx.symbol.text,
    ".",
  }, { cwd = ctx.cwd }, function(result)
    vim.schedule(function()
      if result.code ~= 0 and (result.stdout == nil or result.stdout == "") then
        callback({})
        return
      end

      local out = {}
      for _, line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
        local relative, row, col = line:match("^([^:]+):(%d+):(%d+):")
        if relative and row and col then
          local path = paths.normalize(ctx.cwd .. "/" .. relative)
          local lnum = tonumber(row)
          local cnum = tonumber(col)
          if path and lnum and cnum and not (path == ctx.path and current_line and lnum == current_line) then
            local label = text.line_at(path, lnum)
            if label ~= "" then
              out[#out + 1] = {
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
                badge = "REF",
                detail = paths.display(path, ctx.cwd),
                secondary = paths.display(path, ctx.cwd),
                group = "Text Matches",
                icon = config.values.icons.refs,
              }
            end
          end
        end
      end

      callback(dedupe(out))
    end)
  end)
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
      done(flatten_responses(function(result, c)
        return location_items("refs", "reference", "REF", 90, result, c)
      end, responses, ctx))
    end)
  end

  collect(false, function(found)
    collect(true, function(retried)
      grep_references(ctx, function(grep_found)
        local merged = dedupe(vim.list_extend(vim.list_extend({}, found), retried))
        if #merged > 0 then
          push(dedupe(vim.list_extend(merged, grep_found)))
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
      local merged = dedupe(results)
      table.sort(merged, items.score_sort)
      callback(merged)
    end
  end

  gather_definitions(ctx, push)
  gather_callers(ctx, push)
  gather_references(ctx, push)
end

return M
