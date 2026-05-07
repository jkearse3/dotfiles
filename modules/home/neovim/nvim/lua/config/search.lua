-- Core search keymaps that work without any plugin.
vim.keymap.set("n", "<leader>/", "<cmd>nohlsearch<cr>", { desc = "Clear search highlights" })

-- Fzf-lua fuzzy finder.
require("lib.config").run({
	plugins = { "https://github.com/ibhagwan/fzf-lua" },
	setup = function()
		local fzf = require("fzf-lua")

		fzf.setup({
			grep = { hidden = true },
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

		-- Jump from a unified diff buffer to the corresponding file and line.
		-- Searches backward for the +++ header (filepath) and @@ hunk header
		-- (start line), then counts context/added lines to compute offset.
		local function diff_goto_file()
			local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
			local lines = vim.api.nvim_buf_get_lines(0, 0, cursor_row, false)

			-- Find filepath from nearest +++ header above cursor.
			local filepath
			for i = #lines, 1, -1 do
				local match = lines[i]:match("^%+%+%+ b/(.*)")
				if match then
					filepath = match
					break
				end
			end
			if not filepath then
				vim.notify("No file header found above cursor", vim.log.levels.WARN)
				return
			end

			-- Find nearest @@ hunk header above cursor.
			local hunk_start, hunk_line_idx
			for i = #lines, 1, -1 do
				local match = lines[i]:match("^@@ .* %+(%d+)")
				if match then
					hunk_start = tonumber(match)
					hunk_line_idx = i
					break
				end
			end
			if not hunk_start then
				vim.cmd.edit(filepath)
				return
			end

			-- Walk from hunk header to cursor, counting context and added lines.
			-- Removed lines don't exist in the new file, so skip them.
			local offset = 0
			for i = hunk_line_idx + 1, #lines do
				local prefix = lines[i]:sub(1, 1)
				if prefix == " " or prefix == "+" then
					offset = offset + 1
				end
				-- "-" lines: skip (not in new file)
				-- Any other prefix (e.g. next @@ or \ No newline): stop
				if prefix ~= " " and prefix ~= "+" and prefix ~= "-" then
					break
				end
			end

			local target_line = hunk_start + math.max(offset - 1, 0)
			vim.cmd.edit(filepath)
			vim.api.nvim_win_set_cursor(0, { target_line, 0 })
		end

		local function diff_file_picker(ref)
			local ref_arg = (ref and ref ~= "") and (" " .. ref) or ""
			fzf.fzf_exec("git diff --name-only" .. ref_arg, {
				prompt = "Diff files\u{276F} ",
				preview = "git diff --color=always" .. ref_arg .. " -- {1}",
				actions = {
					["enter"] = function(selected)
						local file = selected[1]
						local output = vim.fn.systemlist("git diff" .. ref_arg .. " -- " .. file)
						vim.cmd("enew")
						vim.bo.buftype = "nofile"
						vim.bo.bufhidden = "hide"
						vim.bo.swapfile = false
						vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
						vim.bo.modifiable = false
						vim.bo.filetype = "diff"
						vim.keymap.set(
							"n",
							"gf",
							diff_goto_file,
							{ buffer = 0, desc = "Jump to file from diff" }
						)
					end,
				},
			})
		end

		local function diff_branch()
			fzf.fzf_exec("git branch --all", {
				prompt = "Branches\u{276F} ",
				actions = {
					["enter"] = function(selected)
						local branch = selected[1]:gsub("^%s*%*?%s*", "")
						diff_file_picker(branch .. "...")
					end,
				},
			})
		end

		local function diff_default_branch()
			local default_branch = vim.fn.system("jj-bookmark-default"):gsub("%s+$", "")
			diff_file_picker(default_branch .. "...")
		end

		local function diff_previous_branch()
			local prev_branch = vim.fn.system("jj-bookmark-previous"):gsub("%s+$", "")
			diff_file_picker(prev_branch .. "...")
		end

		local function diff_previous_revision()
			diff_file_picker("HEAD~1 HEAD")
		end

		vim.keymap.set(
			"n",
			"<leader>fgdw",
			diff_file_picker,
			{ desc = "FZF: Diff working changes" }
		)
		vim.keymap.set(
			"n",
			"<leader>fgdb",
			diff_branch,
			{ desc = "FZF: Diff against branch (pick)" }
		)
		vim.keymap.set(
			"n",
			"<leader>fgdd",
			diff_default_branch,
			{ desc = "FZF: Diff against default branch" }
		)
		vim.keymap.set(
			"n",
			"<leader>fgdp",
			diff_previous_branch,
			{ desc = "FZF: Diff against previous branch" }
		)
		vim.keymap.set(
			"n",
			"<leader>fgdr",
			diff_previous_revision,
			{ desc = "FZF: Diff previous revision" }
		)
	end,
})
