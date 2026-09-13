require("lib.config").run({
	plugins = {
		"https://github.com/nvim-treesitter/nvim-treesitter",
	},
	setup = function()
		vim.api.nvim_create_autocmd("PackChanged", {
			callback = function(ev)
				if ev.data.spec.name ~= "nvim-treesitter" then
					return
				end
				if ev.data.kind ~= "install" and ev.data.kind ~= "update" then
					return
				end
				vim.cmd("TSUpdate")
			end,
		})

		require("nvim-treesitter").setup({})

		-- Install parsers for languages we always want available.
		require("nvim-treesitter").install({
			"lua",
			"c",
			"go",
			"gomod",
			"gosum",
			"gowork",
			"html",
			"javascript",
			"json",
			"jsonnet",
			"nix",
			"proto",
			"rust",
			"typescript",
			"yaml",
			"kdl",
		})

		-- Enable treesitter highlighting for all filetypes except tmux (broken parser).
		vim.api.nvim_create_autocmd("FileType", {
			callback = function(args)
				local ft = vim.bo[args.buf].filetype
				if ft == "tmux" then
					return
				end
				pcall(vim.treesitter.start, args.buf)
			end,
		})

		-- Auto-install missing parsers when opening a file.
		vim.api.nvim_create_autocmd("FileType", {
			callback = function(args)
				local ft = vim.bo[args.buf].filetype
				local lang = vim.treesitter.language.get_lang(ft)
				if lang and not pcall(vim.treesitter.language.inspect, lang) then
					require("nvim-treesitter").install({ lang })
				end
			end,
		})
	end,
})
