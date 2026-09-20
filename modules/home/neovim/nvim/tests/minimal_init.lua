-- Load only installed test dependencies, never the personal init or vim.pack.add.
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd.packadd("plenary.nvim")
vim.cmd.packadd("fzf-lua")

-- Initialize before Busted replaces assert; fzf-lua's UTF-8 setup uses its return values.
require("fzf-lua").setup({})
