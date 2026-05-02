local M = {
  current = nil,
  ui_suspended = false,
  cache = {},
  trail = {},
  trail_cursor = 1,
  trail_persistence = {
    active_name = nil,
    project_root = nil,
    detached = true,
    dirty = false,
  },
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

function M.trail_persistence_state()
  return vim.deepcopy(M.trail_persistence)
end

function M.set_trail_persistence(opts)
  opts = opts or {}

  local current = M.trail_persistence
  local function pick(key)
    if opts[key] ~= nil then
      return opts[key]
    end
    return current[key]
  end

  M.trail_persistence = {
    active_name = pick("active_name"),
    project_root = pick("project_root"),
    detached = pick("detached"),
    dirty = pick("dirty"),
  }

  return M.trail_persistence
end

function M.attach_saved_trail(name, opts)
  opts = opts or {}

  return M.set_trail_persistence({
    active_name = name,
    project_root = opts.project_root,
    detached = false,
    dirty = opts.dirty or false,
  })
end

function M.detach_trail(opts)
  opts = opts or {}

  M.trail_persistence = {
    active_name = nil,
    project_root = nil,
    detached = true,
    dirty = opts.dirty or false,
  }

  return M.trail_persistence
end

function M.mark_trail_dirty(dirty)
  M.trail_persistence.dirty = dirty ~= false
  return M.trail_persistence
end

function M.reset_trail_persistence()
  return M.detach_trail({ dirty = false })
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
