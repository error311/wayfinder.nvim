local M = {
  current = nil,
  cache = {},
  trail = {},
  trail_cursor = 1,
  ui = {
    border = nil,
    top = nil,
    facet = nil,
    list = nil,
    preview = nil,
    bottom = nil,
    preview_buf = nil,
    preview_header = nil,
    preview_ns = vim.api.nvim_create_namespace("WayfinderPreview"),
  },
  preview = {
    timer = nil,
    token = 0,
  },
  notice = {
    text = nil,
    expires_at = 0,
  },
  seq = 0,
}

function M.next_id()
  M.seq = M.seq + 1
  return M.seq
end

function M.cache_get(key, ttl_ms)
  local item = M.cache[key]
  if not item then
    return nil
  end

  if (vim.loop.now() - item.at) > ttl_ms then
    M.cache[key] = nil
    return nil
  end

  return item.value
end

function M.cache_set(key, value)
  M.cache[key] = {
    at = vim.loop.now(),
    value = value,
  }
  return value
end

function M.clear_cache()
  M.cache = {}
end

function M.set_notice(text, ttl_ms)
  M.notice = {
    text = text,
    expires_at = vim.loop.now() + (ttl_ms or 1200),
  }
end

function M.notice_text()
  if not M.notice.text then
    return nil
  end

  if vim.loop.now() > (M.notice.expires_at or 0) then
    M.notice = {
      text = nil,
      expires_at = 0,
    }
    return nil
  end

  return M.notice.text
end

return M
