require("lib.config").run({
	plugins = { "https://github.com/stevearc/oil.nvim" },
	setup = function()
		local oil = require("oil")
		local show_details = false
		local default_columns = { "icon" }

		oil.setup({
			columns = default_columns,
			delete_to_trash = true,
			watch_for_changes = false,
			view_options = {
				show_hidden = true,
				natural_order = true,
			},
			keymaps = {
				["gd"] = {
					desc = "Toggle file detail view",
					callback = function()
						show_details = not show_details
						if show_details then
							require("oil").set_columns({ "icon", "permissions", "size", "mtime" })
						else
							require("oil").set_columns(default_columns)
						end
					end,
				},
			},
		})

		-- Override the default `netrw` behavior.
		vim.api.nvim_create_user_command("Explore", "Oil <args>", { nargs = "?", complete = "dir" })
		vim.api.nvim_create_user_command("E", "Explore <args>", { nargs = "?", complete = "dir" })
		vim.api.nvim_create_user_command(
			"Sexplore",
			"belowright split | Oil <args>",
			{ nargs = "?", complete = "dir" }
		)
		vim.api.nvim_create_user_command(
			"Vexplore",
			"rightbelow vsplit | Oil <args>",
			{ nargs = "?", complete = "dir" }
		)
		vim.api.nvim_create_user_command(
			"Texplore",
			"tabedit % | Oil <args>",
			{ nargs = "?", complete = "dir" }
		)

		vim.keymap.set("n", "<leader>e", "<cmd>Explore<cr>", { desc = "Explore" })
		vim.keymap.set(
			"n",
			"<leader>E",
			"<cmd>Explore `=getcwd(-1, 1)`<cr>",
			{ desc = "Explore from workspace dir" }
		)
	end,
})
