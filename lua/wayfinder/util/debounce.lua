local M = {}

function M.new(delay, fn)
  local timer = assert(vim.uv.new_timer(), "wayfinder debounce timer")

  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(delay, 0, vim.schedule_wrap(function()
      fn(unpack(args))
    end))
  end
end

return M
