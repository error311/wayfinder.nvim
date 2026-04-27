local M = {}

function M.system(cmd, opts, on_exit)
  opts = opts or {}
  if vim.system then
    local system_opts = vim.tbl_extend("keep", {
      cwd = opts.cwd,
      timeout = opts.timeout_ms,
      text = true,
    }, opts)
    system_opts.timeout_ms = nil

    vim.system(cmd, system_opts, function(result)
      vim.schedule(function()
        result.timed_out = result.code == 124 or result.code == 143 or result.code == -1
        on_exit(result)
      end)
    end)
    return
  end

  local stdout = {}
  local stderr = {}
  local finished = false
  local timed_out = false
  local job_id = nil
  local timer = nil

  local function finish(result)
    if finished then
      return
    end

    finished = true
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end

    vim.schedule(function()
      result.timed_out = timed_out
      on_exit(result)
    end)
  end

  job_id = vim.fn.jobstart(cmd, {
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
      finish({
        code = code,
        stdout = table.concat(stdout, "\n"),
        stderr = table.concat(stderr, "\n"),
      })
    end,
  })

  if opts.timeout_ms and job_id > 0 then
    timer = vim.uv.new_timer()
    timer:start(opts.timeout_ms, 0, function()
      timed_out = true
      pcall(vim.fn.jobstop, job_id)
      finish({
        code = 124,
        stdout = table.concat(stdout, "\n"),
        stderr = table.concat(stderr, "\n"),
      })
    end)
  elseif job_id <= 0 then
    finish({
      code = -1,
      stdout = "",
      stderr = "jobstart failed",
    })
  end
end

function M.defer(fn)
  vim.schedule(fn)
end

return M
