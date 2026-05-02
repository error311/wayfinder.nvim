local support = dofile(vim.fn.getcwd() .. "/tests/support.lua")

dofile(vim.fn.getcwd() .. "/tests/suite_trail.lua")
dofile(vim.fn.getcwd() .. "/tests/suite_persistence.lua")
dofile(vim.fn.getcwd() .. "/tests/suite_ui.lua")
dofile(vim.fn.getcwd() .. "/tests/suite_filter.lua")
dofile(vim.fn.getcwd() .. "/tests/suite_sources.lua")

support.finish()
