local M = {}

local defaults = {
  cache_ttl_ms = 2000,
  preview_debounce_ms = 40,
  performance = "balanced",
  scope = {
    mode = "project",
    package_markers = {
      "package.json",
      "tsconfig.json",
      "pyproject.toml",
      "go.mod",
      "Cargo.toml",
      ".git",
    },
  },
  limits = {
    refs = {
      max_results = 200,
      timeout_ms = 1200,
    },
    text = {
      enabled = true,
      max_results = 100,
      timeout_ms = 800,
    },
    tests = {
      max_results = 50,
      timeout_ms = 700,
    },
    git = {
      enabled = true,
      max_commits = 15,
      timeout_ms = 400,
    },
  },
  git_commit_limit = 10,
  max_results_per_facet = 80,
  icons = {
    all = "•",
    calls = "↗",
    refs = "⌕",
    tests = "✓",
    git = "⎇",
    trail = "→",
    definition = "D",
    caller = "C",
    reference = "R",
    test = "T",
    commit = "G",
    pinned = "+",
  },
  layout = {
    width = 0.88,
    height = 0.72,
    border = "rounded",
    title = " Wayfinder ",
    facet_width = 16,
    list_width = 39,
    show_hints = true,
  },
}

local performance_presets = {
  fast = {
    limits = {
      refs = { max_results = 120, timeout_ms = 800 },
      text = { max_results = 60, timeout_ms = 450 },
      tests = { max_results = 30, timeout_ms = 450 },
      git = { max_commits = 8, timeout_ms = 250 },
    },
  },
  balanced = {
    limits = {
      refs = { max_results = 200, timeout_ms = 1200 },
      text = { max_results = 100, timeout_ms = 800 },
      tests = { max_results = 50, timeout_ms = 700 },
      git = { max_commits = 15, timeout_ms = 400 },
    },
  },
  full = {
    limits = {
      refs = { max_results = 400, timeout_ms = 2000 },
      text = { max_results = 200, timeout_ms = 1600 },
      tests = { max_results = 100, timeout_ms = 1200 },
      git = { max_commits = 25, timeout_ms = 900 },
    },
  },
}

local function preset_values(name)
  local preset = performance_presets[name] or performance_presets.balanced
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), preset)
end

local function apply_compat(values, opts)
  opts = opts or {}

  if opts.git_commit_limit and not vim.tbl_get(opts, "limits", "git", "max_commits") then
    values.limits.git.max_commits = opts.git_commit_limit
  end

  if opts.max_results_per_facet then
    if not vim.tbl_get(opts, "limits", "refs", "max_results") then
      values.limits.refs.max_results = opts.max_results_per_facet
    end
    if not vim.tbl_get(opts, "limits", "text", "max_results") then
      values.limits.text.max_results = opts.max_results_per_facet
    end
    if not vim.tbl_get(opts, "limits", "tests", "max_results") then
      values.limits.tests.max_results =
        math.min(opts.max_results_per_facet, values.limits.tests.max_results)
    end
  end
end

M.values = preset_values(defaults.performance)

function M.setup(opts)
  opts = opts or {}
  local values = preset_values(opts.performance or defaults.performance)
  values = vim.tbl_deep_extend("force", values, opts)
  apply_compat(values, opts)
  M.values = values
end

return M
