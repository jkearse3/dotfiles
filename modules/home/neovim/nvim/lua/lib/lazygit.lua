local M = {}

---@class lib.lazygit.Session
---@field buf integer Terminal buffer; hiding it keeps the process alive.
---@field win? integer
---@field previous_win integer
---@field cwd string

---@type lib.lazygit.Session|nil
local session

---@type table<string, lib.lazygit.Session>
local sessions = {}

---@return vim.api.keyset.win_config
local function window_config()
	return {
		relative = "editor",
		row = 0,
		col = 0,
		width = math.max(1, vim.o.columns - 2),
		height = math.max(1, vim.o.lines - 2),
		style = "minimal",
		border = "rounded",
	}
end

---@param current lib.lazygit.Session
local function hide_window(current)
	if current.win and vim.api.nvim_win_is_valid(current.win) then
		vim.api.nvim_win_close(current.win, true)
	end
	current.win = nil
end

---@param current lib.lazygit.Session
local function show_window(current)
	if current.win and vim.api.nvim_win_is_valid(current.win) then
		vim.api.nvim_set_current_win(current.win)
	else
		current.previous_win = vim.api.nvim_get_current_win()
		current.win = vim.api.nvim_open_win(current.buf, true, window_config())
	end
	vim.cmd.startinsert()
end

--- Releases only this session's resources, without stealing focus after a file edit.
---@param current lib.lazygit.Session
local function finish_session(current)
	local was_focused = current.win == vim.api.nvim_get_current_win()
	hide_window(current)
	if was_focused and vim.api.nvim_win_is_valid(current.previous_win) then
		vim.api.nvim_set_current_win(current.previous_win)
	end
	if sessions[current.cwd] == current then
		sessions[current.cwd] = nil
	end
	if session == current then
		session = nil
	end
	if vim.api.nvim_buf_is_valid(current.buf) then
		vim.api.nvim_buf_delete(current.buf, { force = true })
	end
	vim.cmd("checktime")
end

--- Resolve worktrees through Git rather than assuming .git is a directory.
---@return string
local function repository_directory()
	local cwd = vim.fn.getcwd()
	local path = vim.api.nvim_buf_get_name(0)
	local resolved = vim.fn.resolve(path)
	if path ~= "" and resolved ~= path then
		cwd = vim.fs.dirname(resolved)
	end

	local result = vim.system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" }, {
		text = true,
	}):wait()
	return result.code == 0 and vim.trim(result.stdout) or cwd
end

--- Opens or resumes a fullscreen LazyGit terminal for the current repository.
--- Hidden terminals are reused per repository without changing Neovim's cwd.
--- Failed starts and exited jobs release their buffers.
function M.open()
	if session and session.win and vim.api.nvim_win_is_valid(session.win) then
		show_window(session)
		return
	end
	if vim.fn.executable("lazygit") ~= 1 then
		vim.notify("LazyGit executable not found", vim.log.levels.ERROR)
		return
	end

	local ok_directory, cwd = pcall(repository_directory)
	if not ok_directory then
		vim.notify("Failed to locate LazyGit repository: " .. tostring(cwd), vim.log.levels.ERROR)
		return
	end

	local existing = sessions[cwd]
	if existing and vim.api.nvim_buf_is_valid(existing.buf) then
		session = existing
		show_window(existing)
		return
	end

	local command = { "lazygit" }
	if vim.env.GIT_DIR and vim.env.GIT_WORK_TREE then
		vim.list_extend(command, {
			"-w",
			vim.fn.fnamemodify(vim.env.GIT_WORK_TREE, ":p"),
			"-g",
			vim.fn.fnamemodify(vim.env.GIT_DIR, ":p"),
		})
	end

	local current = {
		buf = vim.api.nvim_create_buf(false, true),
		previous_win = vim.api.nvim_get_current_win(),
		cwd = cwd,
	}
	session = current
	sessions[cwd] = current
	vim.bo[current.buf].bufhidden = "hide"
	vim.bo[current.buf].filetype = "lazygit"
	show_window(current)

	local ok, job = pcall(vim.fn.jobstart, command, {
		term = true,
		cwd = current.cwd,
		on_exit = function(_, code)
			vim.schedule(function()
				finish_session(current)
				if code ~= 0 then
					vim.notify("LazyGit exited with code " .. code, vim.log.levels.ERROR)
				end
			end)
		end,
	})
	if not ok or job <= 0 then
		finish_session(current)
		vim.notify("Failed to start LazyGit: " .. tostring(job), vim.log.levels.ERROR)
	end
end

--- Opens a LazyGit-selected file in the originating window, retaining the terminal.
--- Relative paths resolve against the terminal's repository; line numbers are 1-based.
---@param file_path string
---@param line? integer
function M.edit(file_path, line)
	if session then
		if file_path:sub(1, 1) ~= "/" then
			file_path = vim.fs.joinpath(session.cwd, file_path)
		end
		hide_window(session)
		if vim.api.nvim_win_is_valid(session.previous_win) then
			vim.api.nvim_set_current_win(session.previous_win)
		end
	end

	-- Pass filenames as data so spaces and Ex metacharacters cannot become commands.
	if vim.api.nvim_buf_get_name(0) ~= vim.fn.fnamemodify(file_path, ":p") then
		vim.api.nvim_cmd({
			cmd = "edit",
			args = { file_path },
			magic = {
				file = false,
				bar = false,
			},
		}, {})
	end
	if line then
		local last_line = vim.api.nvim_buf_line_count(0)
		vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(line, last_line)), 0 })
	end
end

vim.api.nvim_create_autocmd("VimResized", {
	group = vim.api.nvim_create_augroup("LazyGitTerminal", { clear = true }),
	callback = function()
		if session and session.win and vim.api.nvim_win_is_valid(session.win) then
			vim.api.nvim_win_set_config(session.win, window_config())
		end
	end,
})

return M
