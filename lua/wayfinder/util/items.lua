local M = {}

function M.item_id(parts)
  return table.concat(parts, "::")
end

function M.score_sort(a, b)
  if a.score == b.score then
    if a.group == b.group then
      if a.path == b.path then
        return (a.lnum or 0) < (b.lnum or 0)
      end
      return (a.path or "") < (b.path or "")
    end
    return (a.group or "") < (b.group or "")
  end

  return (a.score or 0) > (b.score or 0)
end

function M.badge_text(item)
  if not item then
    return ""
  end

  if item.source == "lsp" then
    return "[LSP]"
  end
  if item.source == "grep" then
    return "[TXT]"
  end
  if item.source == "test" then
    return "[TEST]"
  end
  if item.source == "git" then
    return "[GIT]"
  end

  return item.badge and ("[" .. item.badge .. "]") or ""
end

return M
