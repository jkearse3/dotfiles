-- Core display settings that work regardless of colorscheme plugin.
vim.opt.termguicolors = true

vim.opt.list = true
vim.opt.listchars = {
	space = "·",
	tab = "▸ ",
	trail = "·",
	extends = ">",
	precedes = "<",
	nbsp = "␣",
}

-- Tokyonight colorscheme.
require("lib.config").run({
	plugins = { "tokyonight.nvim" },
	setup = function()
		vim.cmd("colorscheme tokyonight-night")
	end,
})
