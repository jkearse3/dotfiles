-- Core search keymaps that work without any plugin.
vim.keymap.set("n", "<leader>/", "<cmd>nohlsearch<cr>", { desc = "Clear search highlights" })

-- Fzf-lua fuzzy finder.
require("lib.config").run({
	plugins = { "https://github.com/ibhagwan/fzf-lua" },
	setup = function()
		local fzf = require("fzf-lua")

		fzf.setup({
			grep = { hidden = true },
			git = {
				status = {
					_fmt = {
						from = function(entry)
							return entry:match("%s%-%>%s(.+)$") or entry
						end,
					},
				},
			},
			winopts = {
				fullscreen = true,
				preview = {
					layout = "vertical",
					vertical = "down:80%",
				},
			},
			keymap = {
				fzf = {
					true,
					["ctrl-q"] = "select-all+accept",
					["ctrl-l"] = "accept",
				},
			},
			actions = {
				files = {
					true,
					["ctrl-i"] = fzf.actions.toggle_ignore,
					["ctrl-h"] = fzf.actions.toggle_hidden,
				},
			},
		})

		fzf.register_ui_select()

		vim.keymap.set("n", "<leader>fe", function()
			fzf.fzf_exec("fd --type d --hidden --exclude .git", {
				prompt = vim.fn.fnamemodify(vim.fn.getcwd(), ":~") .. "/",
				actions = {
					["default"] = function(selected)
						vim.cmd.Explore(selected[1])
					end,
				},
			})
		end, { desc = "FZF: Explore directory" })
		vim.keymap.set("n", "<leader>ff", fzf.files, { desc = "FZF: Files" })
		vim.keymap.set("n", "<leader>fs", fzf.lgrep_curbuf, { desc = "FZF: Live grep file" })
		vim.keymap.set("v", "<leader>fs", function()
			fzf.lgrep_curbuf({ search = fzf.utils.get_visual_selection() })
		end, { desc = "FZF: Live grep file (visual selection)" })
		vim.keymap.set("n", "<leader>fS", fzf.live_grep, { desc = "FZF: Live grep workspace" })
		vim.keymap.set("v", "<leader>fS", function()
			fzf.live_grep({ search = fzf.utils.get_visual_selection() })
		end, { desc = "FZF: Live grep workspace (visual selection)" })
		vim.keymap.set("n", "<leader>fw", fzf.grep_cword, { desc = "FZF: Grep word" })
		vim.keymap.set("n", "<leader>fW", fzf.grep_cWORD, { desc = "FZF: Grep WORD" })
		vim.keymap.set("n", "<leader>fm", fzf.marks, { desc = "FZF: Marks" })
		vim.keymap.set("n", "<leader>fr", fzf.registers, { desc = "FZF: Registers" })
		vim.keymap.set("n", "<leader>f<leader>", fzf.resume, { desc = "FZF: Resume last search" })
		vim.keymap.set("n", "<leader>fh", fzf.helptags, { desc = "FZF: Help tags" })
		vim.keymap.set("n", "<leader>fk", fzf.keymaps, { desc = "FZF: Keymaps" })
		vim.keymap.set("n", "<leader>fb", fzf.buffers, { desc = "FZF: Open buffers" })
		vim.keymap.set("n", "<leader>fql", fzf.quickfix, { desc = "FZF: Quickfix list" })
		vim.keymap.set("n", "<leader>fqs", fzf.quickfix_stack, { desc = "FZF: Quickfix stack" })
		vim.keymap.set(
			"n",
			"<leader>fls",
			fzf.lsp_document_symbols,
			{ desc = "FZF: LSP document symbols" }
		)
		vim.keymap.set(
			"n",
			"<leader>flS",
			fzf.lsp_live_workspace_symbols,
			{ desc = "FZF: LSP workspace symbols" }
		)
		vim.keymap.set("n", "<leader>flr", fzf.lsp_references, { desc = "FZF: LSP references" })
		vim.keymap.set("n", "<leader>fld", fzf.lsp_definitions, { desc = "FZF: LSP definitions" })
		vim.keymap.set("n", "<leader>flD", fzf.lsp_declarations, { desc = "FZF: LSP declarations" })
		vim.keymap.set("n", "<leader>flt", fzf.lsp_typedefs, { desc = "FZF: LSP type definitions" })
		vim.keymap.set(
			"n",
			"<leader>fli",
			fzf.lsp_implementations,
			{ desc = "FZF: LSP type implementations" }
		)
		vim.keymap.set(
			"n",
			"<leader>flp",
			fzf.lsp_document_diagnostics,
			{ desc = "FZF: LSP document diagnostics" }
		)
		vim.keymap.set(
			"n",
			"<leader>flP",
			fzf.lsp_workspace_diagnostics,
			{ desc = "FZF: LSP workspace diagnostics" }
		)
		vim.keymap.set("n", "<leader>fgs", fzf.git_status, { desc = "FZF: Git status" })
		vim.keymap.set("n", "<leader>fgS", fzf.git_stash, { desc = "FZF: Git stash" })
		vim.keymap.set("n", "<leader>fgf", fzf.git_files, { desc = "FZF: Git files" })
		vim.keymap.set("n", "<leader>fgb", fzf.git_branches, { desc = "FZF: Git branches" })
		vim.keymap.set("n", "<leader>fgB", fzf.git_blame, { desc = "FZF: Git blame" })
		vim.keymap.set("n", "<leader>fgt", fzf.git_tags, { desc = "FZF: Git tags" })
		vim.keymap.set("n", "<leader>fgh", fzf.git_hunks, { desc = "FZF: Git hunks" })
		vim.keymap.set("n", "<leader>fdb", fzf.dap_breakpoints, { desc = "FZF: DAP breakpoints" })
	end,
})
