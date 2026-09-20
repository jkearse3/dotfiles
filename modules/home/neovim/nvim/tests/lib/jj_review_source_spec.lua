local sources = require("lib.jj_review_source")
local history = require("lib.jj_history")
local review = require("lib.jj_review")
local process = require("lib.jj_review_process")
local fzf = require("fzf-lua")

describe("unified JJ review sources", function()
	local directory, repo, config, buffer, window, original_start, original_exec, original_notify
	local base, middle, target, messages
	local function command(args)
		local result = vim.system(args, { cwd = repo, text = true }):wait()
		assert.are.equal(0, result.code, result.stderr)
		return vim.trim(result.stdout)
	end
	local function jj(...)
		return command({ "jj", "--no-pager", "--color", "never", ... })
	end
	local function id()
		return jj("log", "--no-graph", "-r", "@", "-T", "commit_id")
	end
	local function operation()
		return assert(history.run({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, repo))
	end
	local function text()
		return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	end
	local function wait_for(value)
		assert.is_true(
			vim.wait(5000, function()
				return text():find(value, 1, true) ~= nil
			end),
			text()
		)
	end
	local function resolve(source)
		local done, result, failure
		sources.start(repo, source, function(value, err)
			result, failure, done = value, err, true
		end)
		assert.is_true(vim.wait(5000, function()
			return done
		end))
		return result, failure
	end
	local function edit(path)
		vim.cmd.edit(vim.fn.fnameescape(repo .. "/" .. path))
	end
	local function expand(path)
		for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
			if line:sub(1, 3) == "[+]" and line:find(path, 1, true) then
				vim.api.nvim_win_set_cursor(0, { row, 0 })
				review.toggle(vim.api.nvim_get_current_buf())
				return
			end
		end
		error("Missing header " .. path)
	end
	before_each(function()
		directory = vim.fn.tempname()
		repo = directory .. "/repo"
		vim.fn.mkdir(repo, "p")
		repo = assert(vim.uv.fs_realpath(repo))
		config = vim.env.JJ_CONFIG
		vim.env.JJ_CONFIG = directory .. "/jj.toml"
		vim.fn.writefile(
			{ "[user]", 'name = "Review Test"', 'email = "test@example.invalid"' },
			vim.env.JJ_CONFIG
		)
		command({ "git", "init", "--quiet" })
		command({ "jj-ensure" })
		vim.fn.writefile({ "first" }, repo .. "/file.txt")
		jj("describe", "-m", "base")
		base = id()
		jj("bookmark", "create", "base", "alias", "-r", "@")
		jj("new", "-m", "middle")
		vim.fn.writefile({ "first", "second" }, repo .. "/file.txt")
		jj("describe", "-m", "middle")
		middle = id()
		jj("new", "-m", "feature")
		vim.fn.writefile({ "first", "second", "third" }, repo .. "/file.txt")
		jj("describe", "-m", "feature")
		target = id()
		jj("bookmark", "create", "feature", "-r", "@")
		buffer, window = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
		original_start, original_exec, original_notify = process.start, fzf.fzf_exec, vim.notify
		messages = {}
		vim.notify = function(message)
			messages[#messages + 1] = message
		end
		vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
		edit("file.txt")
	end)
	after_each(function()
		sources.cancel_pending()
		process.start, fzf.fzf_exec, vim.notify = original_start, original_exec, original_notify
		vim.env.JJ_CONFIG = config
		vim.api.nvim_set_current_win(window)
		vim.api.nvim_set_current_buf(buffer)
		vim.cmd("silent! only")
		for _, value in ipairs(vim.api.nvim_list_bufs()) do
			if value ~= buffer then
				vim.api.nvim_buf_delete(value, { force = true })
			end
		end
		vim.fn.delete(directory, "rf")
	end)

	it("opens bookmark ranges lazily and refreshes when only the base moves", function()
		local before = operation()
		local comparison = assert(resolve({ kind = "bookmark", name = "feature" }))
		assert.are.equal(base, comparison.from)
		assert.are.equal(target, comparison.revision.commit_id)
		assert.matches("alias,base..feature", comparison.title, 1, true)
		local review_buffer = review.open_comparison(repo, comparison)
		wait_for("not loaded")
		assert.is_nil(text():find("\nthird\n", 1, true))
		expand("file.txt")
		wait_for("\nthird\n")
		assert.are.equal(before, operation())
		jj("bookmark", "create", "middle", "-r", middle)
		review.refresh(review_buffer)
		wait_for("middle..feature")
		wait_for("not loaded")
		assert.matches("Compare: " .. middle .. " -> " .. target, text(), 1, true)
		assert.is_nil(text():find("\nthird\n", 1, true))
		jj("bookmark", "delete", "feature")
		review.refresh(review_buffer)
		wait_for("Refresh failed; retained pinned comparison")
		assert.matches("Compare: " .. middle .. " -> " .. target, text(), 1, true)
	end)

	it(
		"pins all source-resolution requests to one operation during concurrent bookmark movement",
		function()
			local pinned, moved, operations = operation(), false, {}
			process.start = function(root, args, limit, complete, op)
				if op then
					operations[#operations + 1] = op
				end
				if args[1] == "bookmark" and not moved then
					moved = true
					jj("bookmark", "set", "feature", "-r", base, "--allow-backwards")
				end
				return original_start(root, args, limit, complete, op)
			end
			local comparison = assert(resolve({ kind = "bookmark", name = "feature" }))
			assert.are.equal(target, comparison.revision.commit_id)
			assert.is_true(#operations >= 3)
			for _, op in ipairs(operations) do
				assert.are.equal(pinned, op)
			end
		end
	)

	it("uses bookmark picker entry identity and never displays a patch in its picker", function()
		local entries, options
		fzf.fzf_exec = function(items, opts)
			entries, options = items, opts
		end
		sources.pick_bookmark()
		assert.is_true(vim.wait(5000, function()
			return entries ~= nil
		end))
		assert.is_nil(options.previewer)
		assert.are.same({ "enter" }, vim.tbl_keys(options.actions()))
		local previous = vim.api.nvim_get_current_buf()
		options.actions().enter({ "not an entry" })
		assert.are.equal(previous, vim.api.nvim_get_current_buf())
		for _, item in ipairs(entries) do
			if item:find("\tfeature", 1, true) then
				options.actions().enter({ item })
				break
			end
		end
		wait_for("not loaded")
		assert.matches("alias,base..feature", text(), 1, true)
	end)

	it("rejects missing bases without replacing the existing review", function()
		local current = vim.api.nvim_get_current_buf()
		local result, err = resolve({ kind = "bookmark", name = "base" })
		assert.is_nil(result)
		assert.matches("no first-parent ancestor bookmark", err, 1, true)
		assert.are.equal(current, vim.api.nvim_get_current_buf())
	end)

	it(
		"attributes a recorded line without snapshots and focuses a collapsed historical header",
		function()
			local before = operation()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			sources.open_line()
			wait_for("not loaded")
			assert.matches(base, text(), 1, true)
			assert.matches("Origin in this revision: file.txt:1", text(), 1, true)
			assert.matches("[+]", vim.api.nvim_get_current_line(), 1, true)
			assert.is_nil(text():find("\nfirst\n", 1, true))
			expand("file.txt")
			wait_for("\nfirst\n")
			assert.are.equal(before, operation())
		end
	)

	it("resolves renamed and shifted recorded lines through the complete comparison", function()
		jj("new", "-m", "rename")
		local path = 'moved (all) "quote".txt'
		assert(vim.uv.fs_rename(repo .. "/file.txt", repo .. "/" .. path))
		vim.fn.writefile({ "inserted", "first", "second", "third" }, repo .. "/" .. path)
		jj("describe", "-m", "rename")
		edit(path)
		local before = operation()
		local comparison, err = resolve({ kind = "line", path = path, line = 2 })
		assert.is_not_nil(comparison, err)
		local bytes = assert(history.run({
			"file",
			"show",
			"-r",
			comparison.revision.commit_id,
			"-T",
			'""',
			"--",
			sources.fileset(comparison.focus.path),
		}, repo))
		assert.are.equal("first", vim.split(bytes, "\n", { plain = true })[comparison.focus.line])
		local review_buffer = review.open_comparison(repo, comparison)
		wait_for("not loaded")
		expand(comparison.focus.path)
		wait_for("\nfirst\n")
		for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
			if line == "first" then
				vim.api.nvim_win_set_cursor(0, { row, 0 })
				break
			end
		end
		vim.fn.maparg("gf", "n", false, true).callback()
		assert.is_true(vim.wait(5000, function()
			return vim.api.nvim_get_current_buf() ~= review_buffer
		end))
		assert.are.equal(repo .. "/" .. path, vim.api.nvim_buf_get_name(0))
		assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
		assert.are.equal(review_buffer, vim.fn.bufnr("#"))
		vim.api.nvim_feedkeys(vim.keycode("<C-^>"), "nx", false)
		assert.are.equal(review_buffer, vim.api.nvim_get_current_buf())
		assert.are.equal(before, operation())
	end)

	for _, modified in ipairs({ true, false }) do
		it("rechecks a loaded jump destination (modified=" .. tostring(modified) .. ")", function()
			local file_buffer = vim.api.nvim_get_current_buf()
			local comparison = assert(resolve({ kind = "fixed", name = target }))
			local review_buffer = review.open_comparison(repo, comparison)
			wait_for("not loaded")
			expand("file.txt")
			wait_for("\nthird\n")
			vim.api.nvim_buf_delete(file_buffer, { force = true })
			local loaded = false
			local autocmd = vim.api.nvim_create_autocmd("BufReadPost", {
				pattern = repo .. "/file.txt",
				once = true,
				callback = function(event)
					vim.api.nvim_buf_set_lines(event.buf, 0, 0, false, { "inserted by load hook" })
					vim.bo[event.buf].modified = modified
					loaded = true
				end,
			})
			for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
				if line == "third" then
					vim.api.nvim_win_set_cursor(0, { row, 0 })
					break
				end
			end
			vim.fn.maparg("gf", "n", false, true).callback()
			local finished = vim.wait(5000, function()
				return loaded
			end)
			pcall(vim.api.nvim_del_autocmd, autocmd)
			assert.is_true(finished)
			assert.are.equal(review_buffer, vim.api.nvim_get_current_buf())
			assert.matches(
				modified and "unsaved changes" or "Buffer differs",
				messages[#messages],
				1,
				true
			)
		end)
	end

	it("rejects modified, unnamed, non-file, and outside-workspace line requests", function()
		process.start = function()
			error("Invalid source must not start a request")
		end
		vim.bo.modified = true
		sources.open_line()
		vim.bo.modified = false
		assert.matches("saved, named file buffer", messages[#messages], 1, true)
		vim.bo.buftype = "nofile"
		sources.open_line()
		vim.bo.buftype = ""
		assert.matches("saved, named file buffer", messages[#messages], 1, true)
		local run = history.run
		history.run = function()
			return "/outside-workspace"
		end
		local ok, err = pcall(sources.open_line)
		history.run = run
		assert.is_true(ok, err)
		assert.matches("outside the JJ workspace", messages[#messages], 1, true)
		vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
		sources.open_line()
		assert.matches("saved, named file buffer", messages[#messages], 1, true)
	end)

	it("rejects saved unrecorded and stale loaded text without replacing the view", function()
		local current = vim.api.nvim_get_current_buf()
		vim.fn.writefile({ "inserted", "first", "second", "third" }, repo .. "/file.txt")
		local before = operation()
		local result, err = resolve({ kind = "line", path = "file.txt", line = 1 })
		assert.is_nil(result)
		assert.matches("Working file differs", err, 1, true)
		assert.are.equal(before, operation())
		jj("describe", "-m", "record changed file")
		result, err = resolve({ kind = "line", path = "file.txt", line = 1 })
		assert.is_nil(result)
		assert.matches("Buffer differs", err, 1, true)
		assert.are.equal(current, vim.api.nvim_get_current_buf())
	end)

	it("cancels pending attribution and suppresses late callbacks and temporary files", function()
		local jobs, completed = {}, false
		process.start = function(...)
			local job = original_start(...)
			jobs[#jobs + 1] = job
			return job
		end
		local request = sources.start(
			repo,
			{ kind = "line", path = "file.txt", line = 1 },
			function()
				completed = true
			end
		)
		request.cancel()
		vim.wait(200, function()
			return false
		end)
		assert.is_false(completed)
		for _, job in ipairs(jobs) do
			if job.path then
				assert.is_nil(vim.uv.fs_stat(job.path))
			end
		end
	end)

	it("refuses oversized attribution analysis rather than silently truncating it", function()
		vim.fn.writefile({ string.rep("payload", 160000) }, repo .. "/large.txt", "b")
		jj(
			"--config",
			"snapshot.max-new-file-size=2000000",
			"describe",
			"-m",
			"large unrelated addition"
		)
		local before = operation()
		local result, err = resolve({ kind = "line", path = "file.txt", line = 1 })
		assert.is_nil(result)
		assert.matches("cache limit", err, 1, true)
		assert.are.equal(before, operation())
	end)

	it("refuses divergent operations without reconciling them", function()
		local op = operation()
		jj("describe", "-m", "left")
		jj("--at-operation", op, "describe", "-m", "right")
		local heads = repo .. "/.jj/repo/op_heads/heads"
		local before = vim.fn.sort(vim.fn.readdir(heads))
		assert.are.equal(2, #before)
		local result, err = resolve({ kind = "bookmark", name = "feature" })
		assert.is_nil(result)
		assert.is_not_nil(err)
		assert.are.same(before, vim.fn.sort(vim.fn.readdir(heads)))
	end)

	it("does not steal focus when attribution finishes after switching buffers", function()
		local finished = false
		process.start = function(root, args, limit, complete, op)
			return original_start(root, args, limit, function(err)
				complete(err)
				if args[1] == "log" and args[4] == base then
					finished = true
				end
			end, op)
		end
		sources.open_line()
		vim.api.nvim_set_current_buf(buffer)
		assert.is_true(vim.wait(5000, function()
			return finished
		end))
		assert.are.equal(buffer, vim.api.nvim_get_current_buf())
	end)

	it("bounds loaded-buffer verification before collecting its text", function()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep("x", 1024 * 1024 + 2) })
		vim.bo.modified = false
		assert.matches(
			"verification limit",
			sources.file_error(repo, "file.txt", "first\nsecond\nthird\n"),
			1,
			true
		)
	end)

	it("keeps exact historical drafts pinned when refreshing after a rewrite", function()
		local draft = assert(resolve({ kind = "fixed", name = target }))
		local review_buffer = review.open_comparison(repo, draft)
		wait_for("not loaded")
		jj("describe", "-m", "rewritten description")
		review.refresh(review_buffer)
		assert.is_true(vim.wait(5000, function()
			return not text():find("Resolving review source", 1, true)
		end))
		wait_for("not loaded")
		assert.matches("Compare: parents -> " .. target, text(), 1, true)
		assert.is_nil(text():find("rewritten description", 1, true))
	end)
end)
