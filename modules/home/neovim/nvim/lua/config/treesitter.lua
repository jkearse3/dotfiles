require("lib.config").run({
	plugins = {
		"https://github.com/nvim-treesitter/nvim-treesitter",
		"https://github.com/nvim-treesitter/nvim-treesitter-textobjects",
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

		-- Textobjects: select keymaps via nvim-treesitter-textobjects new API.
		require("nvim-treesitter-textobjects").setup({
			select = {
				lookahead = true,
			},
		})

		local select_textobject = function(query, desc)
			return {
				function()
					require("nvim-treesitter-textobjects.select").select_textobject(
						query,
						"textobjects"
					)
				end,
				desc,
			}
		end

		local keymaps = {
			["a="] = select_textobject("@assignment.outer", "Select outer part of an assignment"),
			["i="] = select_textobject("@assignment.inner", "Select inner part of an assignment"),
			["l="] = select_textobject("@assignment.lhs", "Select left hand side of an assignment"),
			["r="] = select_textobject(
				"@assignment.rhs",
				"Select right hand side of an assignment"
			),
			["aa"] = select_textobject(
				"@parameter.outer",
				"Select outer part of a parameter/argument"
			),
			["ia"] = select_textobject(
				"@parameter.inner",
				"Select inner part of a parameter/argument"
			),
			["ai"] = select_textobject("@conditional.outer", "Select outer part of a conditional"),
			["ii"] = select_textobject("@conditional.inner", "Select inner part of a conditional"),
			["al"] = select_textobject("@loop.outer", "Select outer part of a loop"),
			["il"] = select_textobject("@loop.inner", "Select inner part of a loop"),
			["af"] = select_textobject("@call.outer", "Select outer part of a function call"),
			["if"] = select_textobject("@call.inner", "Select inner part of a function call"),
			["am"] = select_textobject(
				"@function.outer",
				"Select outer part of a method/function definition"
			),
			["im"] = select_textobject(
				"@function.inner",
				"Select inner part of a method/function definition"
			),
			["ac"] = select_textobject("@class.outer", "Select outer part of a class"),
			["ic"] = select_textobject("@class.inner", "Select inner part of a class"),
		}

		for lhs, mapping in pairs(keymaps) do
			vim.keymap.set({ "x", "o" }, lhs, mapping[1], { desc = mapping[2] })
		end
	end,
})
