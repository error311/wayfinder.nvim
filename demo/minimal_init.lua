local init_path = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.normalize(vim.fn.fnamemodify(init_path, ":p:h:h"))
local fixture_root = repo_root .. "/demo/fixture-app"

vim.opt.runtimepath:prepend(repo_root)
vim.opt.termguicolors = true
vim.opt.laststatus = 0
vim.opt.showmode = false
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.opt.cmdheight = 0
vim.opt.swapfile = false
vim.opt.wrap = false
vim.o.background = "dark"

vim.cmd.colorscheme("habamax")

require("wayfinder").setup()

local function start_demo_lsp(args)
  local path = vim.api.nvim_buf_get_name(args.buf)
  if path == "" or not vim.startswith(vim.fs.normalize(path), fixture_root) then
    return
  end

  vim.lsp.start({
    name = "wayfinder-demo-lsp",
    cmd = { "python3", repo_root .. "/demo/fake_lsp.py" },
    root_dir = fixture_root,
  }, {
    bufnr = args.buf,
  })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "typescript", "javascript" },
  callback = start_demo_lsp,
})
