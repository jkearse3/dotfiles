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
			vim.fn.system({ "git", "diff", "--quiet", "--", file_path })
			local status = vim.v.shell_error
			if status > 1 then
				vim.notify("Failed to check git diff status", vim.log.levels.ERROR)
				return
			end

			local is_file_staged = status == 0
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

-- Diffview Plus
require("lib.config").run({
	plugins = {
		"https://github.com/nvim-lua/plenary.nvim",
		"https://github.com/dlyongemallo/diffview-plus.nvim",
	},
	setup = function()
		require("diffview").setup({
			preferred_adapter = "jj",
			view = {
				default = { layout = "diff1_inline" },
				file_history = { layout = "diff1_inline" },
				inline = { style = "unified" },
			},
			file_panel = {
				win_config = {
					type = "split",
					position = "bottom",
					height = 14,
				},
			},
		})

		local function system_trim(command)
			local output = vim.fn.system(command):gsub("%s+$", "")
			if vim.v.shell_error ~= 0 then
				return ""
			end

			return output
		end

		local function open_range_prompt()
			vim.ui.input({ prompt = "Diffview range: " }, function(input)
				if not input or input:match("^%s*$") then
					return
				end

				vim.cmd("DiffviewOpen " .. input)
			end)
		end

		local function open_previous_to_current_bookmark()
			local previous_bookmark = system_trim("jj-bookmark-previous")
			local current_bookmark = system_trim("jj-bookmark-current")
			if previous_bookmark == "" or current_bookmark == "" then
				vim.notify(
					"Could not resolve previous and current bookmark endpoints; enter an explicit diff range.",
					vim.log.levels.WARN
				)
				open_range_prompt()
				return
			end

			vim.cmd("DiffviewOpen " .. previous_bookmark .. ".." .. current_bookmark)
		end

		local function open_previous_to_working_copy()
			local previous_bookmark = system_trim("jj-bookmark-previous")
			if previous_bookmark == "" then
				vim.notify(
					"Could not resolve previous bookmark endpoint; enter an explicit diff range.",
					vim.log.levels.WARN
				)
				open_range_prompt()
				return
			end

			vim.cmd("DiffviewOpen " .. previous_bookmark .. "..@")
		end

		local function parse_stacked_bookmarks(output)
			local bookmarks = {}
			local lines =
				vim.split(output:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })
			for index, line in ipairs(lines) do
				if index == #lines and line == "" then
					break
				end

				local bookmark = line:gsub("^%s+", ""):gsub("%s+$", "")
				if bookmark == "" or bookmark:match("%s") or bookmark:find(",", 1, true) then
					return nil
				end

				table.insert(bookmarks, bookmark)
			end

			return bookmarks
		end

		local function open_stacked_bookmark_picker()
			local stack_output = vim.fn.system("jj-bookmark-stacked")
			local stack_error = vim.v.shell_error
			local stacked_bookmarks = parse_stacked_bookmarks(stack_output)
			if stack_error ~= 0 or not stacked_bookmarks or #stacked_bookmarks < 2 then
				vim.notify(
					"Could not resolve a stacked bookmark range; enter an explicit diff range.",
					vim.log.levels.WARN
				)
				open_range_prompt()
				return
			end

			local default_bookmark = system_trim("jj-bookmark-default")
			vim.ui.select(
				stacked_bookmarks,
				{ prompt = "Stacked bookmark diff: " },
				function(selected)
					if not selected then
						return
					end

					local selected_index
					for index, bookmark in ipairs(stacked_bookmarks) do
						if bookmark == selected then
							selected_index = index
							break
						end
					end

					local base_bookmark = selected_index and stacked_bookmarks[selected_index + 1]
						or nil
					if selected == default_bookmark or not base_bookmark or base_bookmark == "" then
						vim.notify(
							"Could not resolve selected stacked bookmark endpoints; enter an explicit diff range.",
							vim.log.levels.WARN
						)
						open_range_prompt()
						return
					end

					vim.cmd("DiffviewOpen " .. base_bookmark .. ".." .. selected)
				end
			)
		end

		vim.keymap.set(
			"n",
			"<leader>gdw",
			"<cmd>DiffviewOpen<cr>",
			{ desc = "Diffview: Working changes" }
		)
		vim.keymap.set("n", "<leader>gdx", "<cmd>DiffviewClose<cr>", { desc = "Diffview: Close" })
		vim.keymap.set(
			"n",
			"<leader>gdp",
			open_previous_to_current_bookmark,
			{ desc = "Diffview: Previous to current bookmark" }
		)
		vim.keymap.set(
			"n",
			"<leader>gdc",
			open_previous_to_working_copy,
			{ desc = "Diffview: Previous bookmark to working copy" }
		)
		vim.keymap.set(
			"n",
			"<leader>gds",
			open_stacked_bookmark_picker,
			{ desc = "Diffview: Stacked bookmark" }
		)
		vim.keymap.set(
			"n",
			"<leader>gdr",
			"<cmd>DiffviewOpen @-..@<cr>",
			{ desc = "Diffview: Previous revision" }
		)
		vim.keymap.set("n", "<leader>gdR", open_range_prompt, { desc = "Diffview: Explicit range" })
		vim.keymap.set(
			"n",
			"<leader>gdf",
			"<cmd>DiffviewFileHistory %<cr>",
			{ desc = "Diffview: File history" }
		)
		vim.keymap.set(
			"n",
			"<leader>gdh",
			"<cmd>DiffviewFileHistory<cr>",
			{ desc = "Diffview: Repo history" }
		)
	end,
})

-- Fugitive
require("lib.config").run({
	plugins = { "https://github.com/tpope/vim-fugitive", "https://github.com/tpope/vim-rhubarb" },
	setup = function()
		vim.keymap.set("n", "<leader>glh", "<cmd>Git log<cr>", { desc = "Git: repo history" })
		vim.keymap.set(
			"n",
			"<leader>glf",
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
