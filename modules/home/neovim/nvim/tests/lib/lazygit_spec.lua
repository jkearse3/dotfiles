describe("native LazyGit terminal", function()
	local lazygit, jobs, notifications, git_command, executable, start_result, directory
	local previous_win, previous_buf, initial_buffers, git_error
	local real_process, git_environment
	local repository, previous_cwd

	before_each(function()
		jobs, notifications = {}, {}
		executable, start_result, git_error = 1, 42, nil
		real_process, git_environment = false, {}
		directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		directory = assert(vim.uv.fs_realpath(directory))
		repository, previous_cwd = directory, vim.fn.getcwd()
		previous_win, previous_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
		initial_buffers = vim.api.nvim_list_bufs()
		vim.api.nvim_win_set_buf(previous_win, vim.api.nvim_create_buf(true, false))
		local environment = setmetatable({
			vim = setmetatable({
				env = git_environment,
				fn = setmetatable({
					executable = function()
						return executable
					end,
					jobstart = function(command, options)
						table.insert(jobs, {
							command = command,
							options = options,
							buf = vim.api.nvim_get_current_buf(),
							win = vim.api.nvim_get_current_win(),
						})
						if real_process then
							return vim.fn.jobstart({
								vim.v.progpath,
								"--headless",
								"-u",
								"NONE",
								"-i",
								"NONE",
								"-c",
								"lua vim.defer_fn(function() vim.cmd('qa!') end, 100)",
							}, options)
						end
						if type(start_result) == "string" then
							error(start_result)
						end
						return start_result
					end,
				}, { __index = vim.fn }),
				system = function(command)
					git_command = command
					if git_error then
						error(git_error)
					end
					return {
						wait = function()
							return {
								code = 0,
								stdout = repository .. "\n",
							}
						end,
					}
				end,
				notify = function(message)
					table.insert(notifications, message)
				end,
			}, { __index = vim }),
		}, { __index = _G })
		lazygit = setfenv(assert(loadfile("lua/lib/lazygit.lua")), environment)()
	end)

	after_each(function()
		for _, job in ipairs(jobs) do
			job.options.on_exit(42, 0)
		end
		local drained = false
		vim.schedule(function()
			drained = true
		end)
		vim.wait(100, function()
			return drained
		end)
		vim.cmd.stopinsert()
		vim.api.nvim_set_current_win(previous_win)
		vim.api.nvim_win_set_buf(previous_win, previous_buf)
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if not vim.tbl_contains(initial_buffers, buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.cmd.lcd(previous_cwd)
		vim.fn.delete(directory, "rf")
	end)

	it("runs a real terminal process and cleans up its exit callback", function()
		real_process = true
		lazygit.open()
		assert.are.equal("terminal", vim.bo[jobs[1].buf].buftype)
		assert.is_true(vim.wait(3000, function()
			return not vim.api.nvim_buf_is_valid(jobs[1].buf)
		end))
		assert.are.same({}, notifications)
		assert.are.equal(previous_win, vim.api.nvim_get_current_win())
	end)

	it("preserves explicit Git directory and worktree arguments", function()
		git_environment.GIT_DIR = directory .. "/git metadata"
		git_environment.GIT_WORK_TREE = directory .. "/work tree"
		lazygit.open()
		assert.are.same({
			"lazygit",
			"-w",
			git_environment.GIT_WORK_TREE,
			"-g",
			git_environment.GIT_DIR,
		}, jobs[1].command)
	end)

	it("keeps hidden terminals separate when switching repositories", function()
		lazygit.open()
		vim.api.nvim_win_close(jobs[1].win, true)
		repository = directory .. "/other repository"
		vim.fn.mkdir(repository, "p")
		vim.cmd.lcd(repository)
		lazygit.open()
		assert.are.equal(2, #jobs)
		assert.are.equal(repository, jobs[2].options.cwd)
		vim.api.nvim_win_close(jobs[2].win, true)
		repository = directory
		vim.cmd.lcd(directory)
		lazygit.open()
		assert.are.equal(2, #jobs)
		assert.are.equal(jobs[1].buf, vim.api.nvim_get_current_buf())
	end)

	it("launches argv in the repository without changing editor cwd", function()
		local cwd = vim.fn.getcwd()
		lazygit.open()
		assert.are.same({ "git", "-C", cwd, "rev-parse", "--show-toplevel" }, git_command)
		assert.are.same({ "lazygit" }, jobs[1].command)
		assert.are.equal(directory, jobs[1].options.cwd)
		assert.is_true(jobs[1].options.term)
		assert.are.equal(cwd, vim.fn.getcwd())
		assert.is_false(vim.bo[jobs[1].buf].buflisted)
		assert.are.equal("hide", vim.bo[jobs[1].buf].bufhidden)
	end)

	it("reuses visible and hidden terminals and resizes the float", function()
		lazygit.open()
		local buf = jobs[1].buf
		lazygit.open()
		assert.are.equal(1, #jobs)
		vim.api.nvim_win_close(jobs[1].win, true)
		lazygit.open()
		assert.are.equal(1, #jobs)
		assert.are.equal(buf, vim.api.nvim_get_current_buf())
		vim.api.nvim_exec_autocmds("VimResized", {})
		local config = vim.api.nvim_win_get_config(0)
		assert.are.equal(vim.o.columns - 2, config.width)
		assert.are.equal(vim.o.lines - 2, config.height)
	end)

	it("cleans up on exit, restores focus, and can launch again", function()
		lazygit.open()
		local first = jobs[1]
		first.options.on_exit(42, 0)
		assert.is_true(vim.wait(100, function()
			return not vim.api.nvim_buf_is_valid(first.buf)
		end))
		assert.is_false(vim.api.nvim_win_is_valid(first.win))
		assert.are.equal(previous_win, vim.api.nvim_get_current_win())
		lazygit.open()
		assert.are.equal(2, #jobs)
	end)

	it("reports nonzero exits and still releases the terminal", function()
		lazygit.open()
		jobs[1].options.on_exit(42, 1)
		assert.is_true(vim.wait(100, function()
			return #notifications > 0
		end))
		assert.are.same({ "LazyGit exited with code 1" }, notifications)
		assert.is_false(vim.api.nvim_buf_is_valid(jobs[1].buf))
	end)

	it(
		"does not create a terminal when the executable or repository lookup is unavailable",
		function()
			executable = 0
			lazygit.open()
			assert.are.equal(0, #jobs)
			assert.are.equal("LazyGit executable not found", notifications[1])
			executable, git_error = 1, "git unavailable"
			lazygit.open()
			assert.are.equal(0, #jobs)
			assert.matches("Failed to locate LazyGit repository:", notifications[2], 1, true)
			assert.are.equal(#initial_buffers + 1, #vim.api.nvim_list_bufs())
		end
	)

	it("cleans up failed job starts, including thrown errors", function()
		for _, result in ipairs({ 0, -1, "spawn failed" }) do
			start_result = result
			lazygit.open()
			assert.is_false(vim.api.nvim_buf_is_valid(jobs[#jobs].buf))
			assert.are.equal(previous_win, vim.api.nvim_get_current_win())
		end
		assert.are.equal(3, #notifications)
	end)

	it("opens relative filenames literally and retains the hidden process", function()
		local filename = "space % # | quote' file.lua"
		vim.fn.writefile({ "one", "two", "three" }, directory .. "/" .. filename)
		lazygit.open()
		lazygit.edit(filename, 2)
		assert.are.equal(directory .. "/" .. filename, vim.api.nvim_buf_get_name(0))
		assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
		assert.are.equal(previous_win, vim.api.nvim_get_current_win())
		assert.is_true(vim.api.nvim_buf_is_valid(jobs[1].buf))
		lazygit.open()
		assert.are.equal(1, #jobs)
	end)

	it(
		"accepts absolute filenames and the existing remote callback's prior window close",
		function()
			local path = directory .. "/absolute.lua"
			vim.fn.writefile({ "one" }, path)
			lazygit.open()
			vim.api.nvim_win_close(jobs[1].win, true)
			lazygit.edit(path, 100)
			assert.are.equal(path, vim.api.nvim_buf_get_name(0))
			assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
		end
	)

	it(
		"does not reload a selected file with unsaved edits or steal focus when the hidden job exits",
		function()
			local path = directory .. "/modified.lua"
			vim.fn.writefile({ "one" }, path)
			vim.cmd.edit(path)
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
			lazygit.open()
			lazygit.edit(path)
			assert.are.same({ "unsaved" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
			jobs[1].options.on_exit(42, 0)
			assert.is_true(vim.wait(100, function()
				return not vim.api.nvim_buf_is_valid(jobs[1].buf)
			end))
			assert.are.equal(previous_win, vim.api.nvim_get_current_win())
			assert.are.equal(path, vim.api.nvim_buf_get_name(0))
		end
	)
end)
