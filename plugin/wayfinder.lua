if vim.g.loaded_wayfinder then
  return
end

vim.g.loaded_wayfinder = 1

local wayfinder = require("wayfinder")

wayfinder.setup()

vim.keymap.set("n", "<Plug>(WayfinderOpen)", function()
  wayfinder.open()
end, { silent = true, desc = "Open Wayfinder" })

vim.api.nvim_create_user_command("Wayfinder", function()
  wayfinder.open()
end, { desc = "Open Wayfinder for the current symbol or file" })
