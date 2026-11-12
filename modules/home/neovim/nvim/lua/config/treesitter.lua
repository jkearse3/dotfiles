require("lib.config").run({
	plugins = { "nvim-treesitter" },
	setup = function()
		require("nvim-treesitter").setup({})

		-- Enable normal buffer highlighting except for tmux (broken parser) and the
		-- multi-language JJ review buffer, which projects Tree-sitter captures itself.
		vim.api.nvim_create_autocmd("FileType", {
			callback = function(args)
				local ft = vim.bo[args.buf].filetype
				if ft == "tmux" or ft == "jjdiff" then
					return
				end
				pcall(vim.treesitter.start, args.buf)
			end,
		})
	end,
})
