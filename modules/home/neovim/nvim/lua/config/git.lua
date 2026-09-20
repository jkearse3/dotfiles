-- Gitsigns
require("lib.config").run({
	plugins = { "https://github.com/lewis6991/gitsigns.nvim" },
	setup = function()
		local gitsigns = require("gitsigns")

		gitsigns.setup({
			signcolumn = false,
			numhl = true,
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
		vim.keymap.set("n", "<leader>gbf", gitsigns.blame, { desc = "Git: Blame file" })

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

-- JJ diff review
require("lib.config").run({
	plugins = { "https://github.com/ibhagwan/fzf-lua" },
	setup = function()
		local jj_diff = require("lib.jj_diff")
		vim.keymap.set("n", "<leader>gdb", jj_diff.pick_bookmark, { desc = "JJ diff: Bookmark" })
		vim.keymap.set("n", "<leader>gdl", jj_diff.open_cursor_revision, { desc = "JJ diff: Line" })
		vim.keymap.set("n", "<leader>gds", jj_diff.pick_retained_scope, { desc = "JJ diff: Scope" })
	end,
})

local jj_history = require("lib.jj_history")
vim.keymap.set("n", "<leader>jl", jj_history.pick_stack, { desc = "JJ: Change stack" })

-- Read-only history; action allowlists are installed by config.search.
local git_history = require("lib.git_history")
vim.keymap.set("n", "<leader>glh", git_history.pick_repository, { desc = "Git: Repo history" })
vim.keymap.set("n", "<leader>glf", git_history.pick_file, { desc = "Git: File history" })

local git_permalink = require("lib.git_permalink")
vim.api.nvim_create_user_command("CopyGitPermalink", function(opts)
	git_permalink.copy(opts.line1, opts.line2)
end, {
	desc = "Copy commit-pinned GitHub permalink",
	range = true,
})
vim.keymap.set("n", "<leader>gy", function()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	git_permalink.copy(line, line)
end, { desc = "Git: Yank remote permalink" })
vim.keymap.set("x", "<leader>gy", function()
	git_permalink.copy(vim.fn.getpos("v")[2], vim.api.nvim_win_get_cursor(0)[1])
end, { desc = "Git: Yank selected remote permalink" })

-- Plenary remains available for the headless regression suite.
require("lib.config").run({
	plugins = { "https://github.com/nvim-lua/plenary.nvim" },
})

-- Native terminal integration; the LazyGit application remains installed by Nix.
local lazygit = require("lib.lazygit")
_G.edit_from_lazygit = lazygit.edit
vim.api.nvim_create_user_command("LazyGit", lazygit.open, { desc = "Open LazyGit" })
vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { desc = "LazyGit" })
