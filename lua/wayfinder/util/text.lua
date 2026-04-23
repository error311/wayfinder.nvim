local M = {}

local function display_width(value)
  return vim.fn.strdisplaywidth(value or "")
end

local function slice_chars(value, count)
  return vim.fn.strcharpart(value or "", 0, math.max(count or 0, 0))
end

function M.read_lines(path, start_line, end_line)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end

  local result = {}
  for line = start_line, math.min(end_line, #lines) do
    table.insert(result, lines[line] or "")
  end
  return result
end

function M.line_at(path, lnum)
  local lines = M.read_lines(path, lnum, lnum)
  return vim.trim(lines[1] or "")
end

function M.one_line(value)
  return tostring(value or ""):gsub("[%s\r\n\t]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.truncate_end(value, max_width)
  value = M.one_line(value)
  if max_width <= 0 then
    return ""
  end
  if display_width(value) <= max_width then
    return value
  end
  if max_width <= 1 then
    return "…"
  end

  local limit = max_width - 1
  local out = ""
  local index = 0
  while index < #value do
    local next_value = slice_chars(value, vim.fn.strchars(out) + 1)
    if display_width(next_value) > limit then
      break
    end
    out = next_value
    index = #out
  end

  return out .. "…"
end

function M.truncate_middle(value, max_width)
  value = M.one_line(value)
  if max_width <= 0 then
    return ""
  end
  if display_width(value) <= max_width then
    return value
  end
  if max_width <= 1 then
    return "…"
  end

  local chars = vim.fn.strchars(value)
  local left_budget = math.max(math.floor((max_width - 1) / 2), 1)
  local right_budget = math.max(max_width - left_budget - 1, 1)
  local left = slice_chars(value, left_budget)
  local right = vim.fn.strcharpart(value, math.max(chars - right_budget, 0), right_budget)

  while display_width(left .. "…" .. right) > max_width and #left > 0 do
    left = vim.fn.strcharpart(left, 0, math.max(vim.fn.strchars(left) - 1, 0))
  end
  while display_width(left .. "…" .. right) > max_width and #right > 0 do
    right = vim.fn.strcharpart(right, 1)
  end

  return left .. "…" .. right
end

return M
