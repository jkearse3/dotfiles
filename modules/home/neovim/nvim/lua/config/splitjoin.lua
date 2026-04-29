require("lib.config").run({
	plugins = { "https://github.com/echasnovski/mini.nvim" },
	setup = function()
		require("mini.splitjoin").setup()
	end,
})
