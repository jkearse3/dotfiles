local BUFFER_NAME = "[Test Output]"

--- Reuses the hidden test output buffer, or creates it on the first run.
---@return integer
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

---@param bufnr integer
---@param lines string[]
local function write_buffer(bufnr, lines)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

---@param bufnr integer
---@param lines string[]|nil
local function append_buffer(bufnr, lines)
	if not lines or #lines == 0 then
		return
	end

	vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

---@param bufnr integer
local function show_buffer_in_split(bufnr)
	if #vim.fn.win_findbuf(bufnr) > 0 then
		return
	end

	vim.cmd("split")
	vim.api.nvim_win_set_buf(0, bufnr)
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
		return
	end

	show_buffer_in_split(bufnr)
	vim.notify("Test buffer: shown", vim.log.levels.INFO)
end

---@param cmd string
local function strategy_copy(cmd)
	vim.fn.setreg("+", cmd)
	vim.notify("Copied: " .. cmd, vim.log.levels.INFO)
end

--- Collects buffered stdout and stderr in a reusable, read-only split.
---@param cmd string
local function strategy_scratch(cmd)
	local bufnr = get_or_create_buffer()
	write_buffer(bufnr, { "Running: " .. cmd, "---", "" })
	show_buffer_in_split(bufnr)

	-- Both streams use the same append path; absent data needs no special handling.
	local function append_output(_, data)
		append_buffer(bufnr, data)
	end

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = append_output,
		on_stderr = append_output,
		on_exit = function(_, exit_code)
			append_buffer(bufnr, {
				"",
				"--- Test completed with exit code: " .. exit_code .. " ---",
			})
		end,
	})
end

--- Builds a mapping that copies a test command instead of running it.
---@param test_cmd string
---@return fun()
local function yank_test_cmd(test_cmd)
	return function()
		local original = vim.g["test#strategy"]
		vim.g["test#strategy"] = "copy"
		vim.cmd(test_cmd)
		vim.g["test#strategy"] = original
	end
end

---@return string
local function test_project_root()
	if vim.bo.filetype ~= "rust" then
		return vim.fn.getcwd()
	end

	local cargo = vim.fn.findfile("Cargo.toml", vim.fn.expand("%:p:h") .. ";")
	if cargo then
		return vim.fn.fnamemodify(cargo, ":h")
	end
	return vim.fn.getcwd()
end

local function set_test_keymaps()
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
end

local function setup_test()
	vim.g["test#project_root"] = test_project_root
	vim.g["test#custom_strategies"] = {
		copy = strategy_copy,
		scratch = strategy_scratch,
	}
	vim.g["test#strategy"] = "scratch"
	vim.g["test#echo_command"] = 0
	vim.g["test#preserve_screen"] = 1
	vim.g["test#go#gotest#options"] = "-v -count=1"

	set_test_keymaps()
end

require("lib.config").run({
	plugins = { "https://github.com/vim-test/vim-test" },
	setup = setup_test,
})
