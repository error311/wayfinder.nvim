local M = {}

function M.system(cmd, opts, on_exit)
  opts = opts or {}
  if vim.system then
    vim.system(cmd, opts, function(result)
      vim.schedule(function()
        on_exit(result)
      end)
    end)
    return
  end

  local stdout = {}
  local stderr = {}
  vim.fn.jobstart(cmd, {
    cwd = opts.cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr = data
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        on_exit({
          code = code,
          stdout = table.concat(stdout, "\n"),
          stderr = table.concat(stderr, "\n"),
        })
      end)
    end,
  })
end

function M.defer(fn)
  vim.schedule(fn)
end

return M
