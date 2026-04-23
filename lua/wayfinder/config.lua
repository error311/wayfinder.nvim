local M = {}

local defaults = {
  cache_ttl_ms = 2000,
  preview_debounce_ms = 40,
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
  },
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
