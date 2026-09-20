local M = {}
local uv = vim.uv

---@class lib.jj_review.Job
---@field path? string Private output if created; caller deletes it after completion.
---@field cancel fun() Stops the process; completion still fires with an error.

--- Spools a read-only JJ request to disk without collecting stdout in Lua memory.
--- Completion runs on the main loop. Output, duration and stderr are bounded; cancellation
--- terminates the child. The caller must unlink the returned path, including on failure.
---@param repo string
---@param args string[]
---@param limit integer Maximum output bytes.
---@param complete fun(error: string?)
---@param operation? string Exact recorded operation for a multi-request resolution; defaults to @.
---@return lib.jj_review.Job
function M.start(repo, args, limit, complete, operation)
	local path = vim.fn.tempname()
	local fd, open_err = uv.fs_open(path, "wx", 384)
	local job = { path = fd and path or nil, cancel = function() end }
	if not fd then
		vim.schedule(function()
			complete(tostring(open_err))
		end)
		return job
	end
	local command = {
		"--at-operation=" .. (operation or "@"),
		"--ignore-working-copy",
		"--no-pager",
		"--color",
		"never",
	}
	vim.list_extend(command, args)
	local stderr = assert(uv.new_pipe(false))
	local timer = assert(uv.new_timer())
	local message, failure = "", nil
	local process
	local function stop(reason)
		failure = failure or reason
		if process and not process:is_closing() then
			process:kill("sigkill")
		end
	end
	job.cancel = function()
		stop("Cancelled")
		uv.fs_unlink(path)
	end
	process = uv.spawn(
		"jj",
		{ args = command, cwd = repo, stdio = { nil, fd, stderr } },
		function(code, signal)
			timer:stop()
			timer:close()
			stderr:read_stop()
			stderr:close()
			uv.fs_close(fd)
			process:close()
			if signal ~= 0 then
				failure = failure or "JJ terminated by signal " .. signal
			end
			local stat = uv.fs_stat(path)
			if stat and stat.size > limit then
				failure = failure or "JJ output exceeded the cache limit"
			end
			vim.schedule(function()
				complete(
					failure
						or (
							code ~= 0
								and (message ~= "" and message or "JJ exited with status " .. code)
							or nil
						)
				)
			end)
		end
	)
	if not process then
		uv.fs_close(fd)
		stderr:close()
		timer:close()
		vim.schedule(function()
			complete("Unable to start jj")
		end)
		return job
	end
	stderr:read_start(function(err, data)
		if err then
			failure = failure or tostring(err)
		end
		if data then
			message = (message .. data):sub(1, 8192)
		end
	end)
	local ticks = 0
	timer:start(100, 100, function()
		ticks = ticks + 1
		local stat = uv.fs_stat(path)
		if stat and stat.size > limit then
			stop("JJ output exceeded the cache limit")
		end
		if ticks >= 300 then
			stop("JJ inspection timed out")
		end
	end)
	return job
end

--- Reads at most limit bytes from a completed spool. Never reads an unbounded patch.
---@param path string
---@param limit integer
---@param offset? integer
---@return string? content
---@return string? error
function M.read(path, limit, offset)
	local fd, err = uv.fs_open(path, "r", 0)
	if not fd then
		return nil, tostring(err)
	end
	local content, read_err = uv.fs_read(fd, limit, offset or 0)
	uv.fs_close(fd)
	return content, read_err and tostring(read_err) or nil
end

return M
