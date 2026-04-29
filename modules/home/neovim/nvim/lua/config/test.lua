require("lib.config").run({
	plugins = { "https://github.com/vim-test/vim-test" },
	setup = function()
		local BUFFER_NAME = "[Test Output]"

		local function get_or_create_buffer()
			local bufnr = vim.fn.bufnr(BUFFER_NAME)

			if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
				return bufnr
			end

			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, BUFFER_NAME)
			vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
			vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
			vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
			vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

			return bufnr
		end

		local function write_buffer(bufnr, lines)
			vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
			vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
		end

		local function append_buffer(bufnr, lines)
			if not lines or #lines == 0 then
				return
			end

			vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
			vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
			vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
		end

		local function show_buffer_in_split(bufnr)
			local wins = vim.fn.win_findbuf(bufnr)
			if #wins == 0 then
				vim.cmd("split")
				vim.api.nvim_win_set_buf(0, bufnr)
			end
		end

		local function toggle_buffer()
			local bufnr = vim.fn.bufnr(BUFFER_NAME)

			if bufnr == -1 then
				vim.notify("No test buffer found. Run a test first.", vim.log.levels.WARN)
				return
			end

			local wins = vim.fn.win_findbuf(bufnr)

			if #wins > 0 then
				vim.api.nvim_win_close(wins[1], false)
				vim.notify("Test buffer: hidden", vim.log.levels.INFO)
			else
				vim.cmd("split")
				vim.api.nvim_win_set_buf(0, bufnr)
				vim.notify("Test buffer: shown", vim.log.levels.INFO)
			end
		end

		local function strategy_copy(cmd)
			vim.fn.setreg("+", cmd)
			vim.notify("Copied: " .. cmd, vim.log.levels.INFO)
		end

		local function strategy_scratch(cmd)
			local bufnr = get_or_create_buffer()

			write_buffer(bufnr, { "Running: " .. cmd, "---", "" })
			show_buffer_in_split(bufnr)

			vim.fn.jobstart(cmd, {
				stdout_buffered = true,
				stderr_buffered = true,
				on_stdout = function(_, data)
					if data then
						append_buffer(bufnr, data)
					end
				end,
				on_stderr = function(_, data)
					if data then
						append_buffer(bufnr, data)
					end
				end,
				on_exit = function(_, exit_code)
					local status_msg = {
						"",
						"--- Test completed with exit code: " .. exit_code .. " ---",
					}
					append_buffer(bufnr, status_msg)
				end,
			})
		end

		local function yank_test_cmd(test_cmd)
			return function()
				local original = vim.g["test#strategy"]
				vim.g["test#strategy"] = "copy"
				vim.cmd(test_cmd)
				vim.g["test#strategy"] = original
			end
		end

		vim.g["test#project_root"] = function()
			if vim.bo.filetype == "rust" then
				local cargo = vim.fn.findfile("Cargo.toml", vim.fn.expand("%:p:h") .. ";")
				if cargo then
					return vim.fn.fnamemodify(cargo, ":h")
				end
			end
			return vim.fn.getcwd()
		end

		vim.g["test#custom_strategies"] = {
			copy = strategy_copy,
			scratch = strategy_scratch,
		}
		vim.g["test#strategy"] = "scratch"
		vim.g["test#echo_command"] = 0
		vim.g["test#preserve_screen"] = 1

		vim.g["test#go#gotest#options"] = "-v -count=1"

		vim.keymap.set("n", "<leader>trn", "<cmd>TestNearest<cr>", { desc = "Test: Run nearest" })
		vim.keymap.set("n", "<leader>trf", "<cmd>TestFile<cr>", { desc = "Test: Run file" })
		vim.keymap.set("n", "<leader>trs", "<cmd>TestSuite<cr>", { desc = "Test: Run suite" })
		vim.keymap.set("n", "<leader>trl", "<cmd>TestLast<cr>", { desc = "Test: Run last" })
		vim.keymap.set("n", "<leader>tv", "<cmd>TestVisit<cr>", { desc = "Test: Visit test file" })
		vim.keymap.set("n", "<leader>tot", toggle_buffer, { desc = "Test: Toggle output buffer" })

		vim.keymap.set(
			"n",
			"<leader>tyn",
			yank_test_cmd("TestNearest"),
			{ desc = "Test: Yank nearest command" }
		)
		vim.keymap.set(
			"n",
			"<leader>tyf",
			yank_test_cmd("TestFile"),
			{ desc = "Test: Yank file command" }
		)
		vim.keymap.set(
			"n",
			"<leader>tys",
			yank_test_cmd("TestSuite"),
			{ desc = "Test: Yank suite command" }
		)
		vim.keymap.set(
			"n",
			"<leader>tyl",
			yank_test_cmd("TestLast"),
			{ desc = "Test: Yank last command" }
		)
	end,
})
