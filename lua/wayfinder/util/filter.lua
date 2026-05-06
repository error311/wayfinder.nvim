local M = {}

local function push_term(target, token, negated)
  local trimmed = vim.trim(token or "")
  if trimmed == "" then
    return
  end

  if negated then
    target.exclude[#target.exclude + 1] = trimmed:lower()
  else
    target.include[#target.include + 1] = trimmed:lower()
  end
end

function M.parse(query)
  local parsed = {
    include = {},
    exclude = {},
  }

  local text = vim.trim(query or "")
  if text == "" then
    return parsed
  end

  local i = 1
  local len = #text

  while i <= len do
    while i <= len and text:sub(i, i):match("%s") do
      i = i + 1
    end
    if i > len then
      break
    end

    local negated = false
    if text:sub(i, i) == "!" then
      negated = true
      i = i + 1
    end

    if i > len then
      break
    end

    if text:sub(i, i) == '"' then
      local closing = text:find('"', i + 1, true)
      if closing then
        push_term(parsed, text:sub(i + 1, closing - 1), negated)
        i = closing + 1
      else
        push_term(parsed, text:sub(i + 1), negated)
        break
      end
    else
      local j = i
      while j <= len and not text:sub(j, j):match("%s") do
        j = j + 1
      end
      push_term(parsed, text:sub(i, j - 1), negated)
      i = j
    end
  end

  return parsed
end

local function haystack(item)
  return table
    .concat({
      item.label or "",
      item.secondary or "",
      item.reason or "",
      item.detail or "",
    }, "\n")
    :lower()
end

function M.match(item, query)
  local parsed = type(query) == "string" and M.parse(query)
    or query
    or { include = {}, exclude = {} }
  local text = haystack(item or {})

  for _, term in ipairs(parsed.include or {}) do
    if not text:find(term, 1, true) then
      return false
    end
  end

  for _, term in ipairs(parsed.exclude or {}) do
    if text:find(term, 1, true) then
      return false
    end
  end

  return true
end

return M
