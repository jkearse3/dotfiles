-- Gitsigns
require("lib.config").run({
	plugins = { "https://github.com/lewis6991/gitsigns.nvim" },
	setup = function()
		local gitsigns = require("gitsigns")

		gitsigns.setup({
			signcolumn = false,
			numhl = true,
			on_attach = function(bufnr)
				local buf_name = vim.api.nvim_buf_get_name(bufnr)
				if buf_name:match("^diffview://") then
					return false
				end

				return true
			end,
		})

		local function stage_hunk()
			gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end
		vim.keymap.set(
			{ "n", "v" },
			"<leader>gsh",
			stage_hunk,
			{ desc = "Git: Stage hunk (toggleable)" }
		)

		local function reset_hunk()
			gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end
		vim.keymap.set({ "n", "v" }, "<leader>grh", reset_hunk, { desc = "Git: Reset hunk" })

		vim.keymap.set("n", "<leader>gph", gitsigns.preview_hunk, { desc = "Git: Preview hunk" })

		local function stage_buffer()
			local file_path = vim.fn.expand("%:p")
			local handle = io.popen("git diff --name-only -- " .. file_path)
			if not handle then
				vim.notify("Failed to check git status", vim.log.levels.ERROR)
				return
			end

			local result = handle:read("*a")
			handle:close()

			local is_file_staged = result == ""
			if is_file_staged then
				gitsigns.reset_buffer_index()
				vim.notify("Unstaged buffer", vim.log.levels.INFO)
			else
				gitsigns.stage_buffer()
				vim.notify("Staged buffer", vim.log.levels.INFO)
			end
		end
		vim.keymap.set("n", "<leader>gsb", stage_buffer, { desc = "Git: Stage buffer" })
		vim.keymap.set("n", "<leader>grb", gitsigns.reset_buffer, { desc = "Git: Reset buffer" })
		local function blame_line()
			gitsigns.blame_line({ full = true })
		end
		vim.keymap.set("n", "<leader>gbl", blame_line, { desc = "Git: Blame line" })

		vim.keymap.set(
			"n",
			"]g",
			"<cmd>Gitsigns nav_hunk next<cr>",
			{ silent = true, desc = "Git: Next hunk" }
		)
		vim.keymap.set(
			"n",
			"[g",
			"<cmd>Gitsigns nav_hunk prev<cr>",
			{ silent = true, desc = "Git: Previous hunk" }
		)

		local function switch_gutter_base_default()
			local default_branch = vim.fn.system("jj-bookmark-default")
			vim.api.nvim_command("Gitsigns change_base " .. default_branch .. " true")
			vim.notify("Switching git gutter against " .. default_branch)
		end
		vim.keymap.set(
			"n",
			"<leader>gGd",
			switch_gutter_base_default,
			{ desc = "Git: switch gutter base against default branch" }
		)

		local function switch_gutter_base_previous()
			local prev_branch = vim.fn.system("jj-bookmark-previous")
			vim.api.nvim_command("Gitsigns change_base " .. prev_branch .. " true")
			vim.notify("Switching git gutter against " .. prev_branch)
		end
		vim.keymap.set(
			"n",
			"<leader>gGp",
			switch_gutter_base_previous,
			{ desc = "Git: switch gutter base against previous branch" }
		)

		local function switch_gutter_base_previous_revision()
			vim.api.nvim_command("Gitsigns change_base HEAD~1 true")
			vim.notify("Switching git gutter against previous revision")
		end
		vim.keymap.set(
			"n",
			"<leader>gGr",
			switch_gutter_base_previous_revision,
			{ desc = "Git: switch gutter base against previous revision" }
		)

		local function switch_gutter_base_current()
			vim.api.nvim_command("Gitsigns reset_base true")
			vim.notify("Switching git gutter to current")
		end
		vim.keymap.set(
			"n",
			"<leader>gGc",
			switch_gutter_base_current,
			{ desc = "Git: switch gutter base to working dir" }
		)
	end,
})

-- Fugitive
require("lib.config").run({
	plugins = { "https://github.com/tpope/vim-fugitive", "https://github.com/tpope/vim-rhubarb" },
	setup = function()
		vim.keymap.set("n", "<leader>gdh", "<cmd>Git log<cr>", { desc = "Git: repo history" })
		vim.keymap.set(
			"n",
			"<leader>gdf",
			"<cmd>Git log --follow -- %<cr>",
			{ desc = "Git: file history" }
		)

		local function yank_remote_permalink()
			local prefix = ""
			local mode = vim.fn.mode()
			local is_visual_mode = mode == "v" or mode == "V"
			if is_visual_mode then
				local start_line_num = vim.fn.line("'<")
				local end_line_num = vim.fn.line("'>")
				prefix = string.format("%d,%d", start_line_num, end_line_num)
			else
				local line_num = vim.fn.line(".")
				prefix = string.format("%d", line_num)
			end
			vim.cmd(string.format("%sGBrowse!", prefix))
		end
		vim.keymap.set(
			{ "n", "v" },
			"<leader>gy",
			yank_remote_permalink,
			{ desc = "Git: Yank remote permalink" }
		)
	end,
})

-- LazyGit
require("lib.config").run({
	plugins = {
		"https://github.com/nvim-lua/plenary.nvim",
		"https://github.com/kdheepak/lazygit.nvim",
	},
	setup = function()
		_G.edit_from_lazygit = function(file_path, line)
			local path = vim.fn.expand("%:p")
			if path ~= file_path then
				vim.cmd("edit " .. file_path)
			end
			if line then
				vim.cmd(tostring(line))
			end
		end

		vim.g.lazygit_floating_window_scaling_factor = 1

		vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { desc = "LazyGit" })
	end,
})
