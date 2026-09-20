local history = require("lib.jj_history")
local fzf = require("fzf-lua")

describe("read-only JJ history", function()
	local directory, repo, original_config, original_buf, original_win, original_exec
	local original_notify
	local first_commit, first_change, entries, options

	local function command(args)
		local result = vim.system(args, { cwd = repo, text = true }):wait()
		assert.are.equal(0, result.code, result.stderr)
		return vim.trim(result.stdout)
	end
	local function jj(...)
		return command({ "jj", "--no-pager", "--color", "never", ... })
	end

	local function review_text()
		return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	end
	local function wait_overview()
		assert.is_true(vim.wait(5000, function()
			return review_text():find("not loaded", 1, true) ~= nil
		end))
	end
	local function expand_file(path, expected)
		for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
			if line:sub(1, 3) == "[+]" and line:find(path, 1, true) then
				vim.api.nvim_win_set_cursor(0, { row, 0 })
				require("lib.jj_review").toggle(vim.api.nvim_get_current_buf())
				assert.is_true(vim.wait(5000, function()
					return review_text():find(expected, 1, true) ~= nil
				end))
				return
			end
		end
		error("No header for " .. path)
	end

	before_each(function()
		directory = vim.fn.tempname()
		repo = directory .. "/repo"
		vim.fn.mkdir(repo, "p")
		repo = assert(vim.uv.fs_realpath(repo))
		original_config = vim.env.JJ_CONFIG
		vim.env.JJ_CONFIG = directory .. "/config.toml"
		vim.fn.writefile(
			{ "[user]", 'name = "History Test"', 'email = "test@example.invalid"' },
			vim.env.JJ_CONFIG
		)
		command({ "git", "init", "--quiet" })
		command({ "jj-ensure" })
		vim.fn.writefile({ "first" }, repo .. "/file.txt")
		jj("describe", "-m", "first revision")
		first_commit = jj("log", "--no-graph", "-r", "@", "-T", "commit_id")
		first_change = jj("log", "--no-graph", "-r", "@", "-T", "change_id")
		jj("bookmark", "create", "test-stack", "-r", "@")
		jj("new", "-m", "second revision")
		original_buf, original_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
		local buffer = vim.fn.bufadd(repo .. "/file.txt")
		vim.fn.bufload(buffer)
		vim.api.nvim_win_set_buf(0, buffer)
		original_exec = fzf.fzf_exec
		original_notify = vim.notify
		fzf.fzf_exec = function(source, opts)
			entries, options = source, opts
		end
	end)

	after_each(function()
		fzf.fzf_exec = original_exec
		vim.notify = original_notify
		vim.env.JJ_CONFIG = original_config
		vim.api.nvim_set_current_win(original_win)
		vim.api.nvim_win_set_buf(original_win, original_buf)
		vim.cmd("silent! only")
		for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
			if buffer ~= original_buf then
				vim.api.nvim_buf_delete(buffer, { force = true })
			end
		end
		vim.fn.delete(directory, "rf")
	end)

	it("uses the file repository and preserves IDs and bookmarks in the stack", function()
		history.pick_stack()
		assert.are.equal("JJ stack> ", options.prompt)
		local revisions = assert(history.list(repo))
		local found
		for _, revision in ipairs(revisions) do
			if revision.commit_id == first_commit then
				found = revision
			end
		end
		assert.is_not_nil(found)
		assert.are.equal(first_change, found.change_id)
		assert.are.same({ "test-stack" }, found.bookmarks)
		assert.is_true(#entries >= 2)
	end)

	it(
		"previews and opens patches without snapshotting dirty files or changing the operation log",
		function()
			local before =
				assert(history.run({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, repo))
			vim.fn.writefile({ "not snapshotted" }, repo .. "/file.txt")
			history.pick_stack()
			local selected
			for _, entry in ipairs(entries) do
				if entry:find(first_commit:sub(1, 12), 1, true) then
					selected = entry
				end
			end
			local preview = vim.api.nvim_create_buf(false, true)
			options.previewer()._ctor().populate_preview_buf({
				get_tmp_buffer = function()
					return preview
				end,
				set_preview_buf = function() end,
			}, selected)
			assert.matches(
				"first revision",
				table.concat(vim.api.nvim_buf_get_lines(preview, 0, -1, false), "\n"),
				1,
				true
			)
			options.actions().enter({ selected })
			assert.is_false(vim.bo.modifiable)
			assert.is_true(vim.bo.readonly)
			local buffer = vim.api.nvim_get_current_buf()
			local function content()
				return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
			end
			assert.is_true(
				vim.wait(5000, function()
					return content():find("not loaded", 1, true) ~= nil
				end),
				content()
			)
			assert.is_nil(content():find("\nfirst\n", 1, true))
			for row, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
				if line:find("file.txt", 1, true) then
					vim.api.nvim_win_set_cursor(0, { row, 0 })
					break
				end
			end
			require("lib.jj_review").toggle(buffer)
			assert.is_true(
				vim.wait(5000, function()
					return content():find("\nfirst\n", 1, true) ~= nil
				end),
				content()
			)
			assert.are.equal(
				before,
				history.run({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, repo)
			)
			assert.are.same({ "not snapshotted" }, vim.fn.readfile(repo .. "/file.txt"))
		end
	)

	it("replaces inherited picker actions with an explicit inspection allowlist", function()
		history.pick_stack()
		local normalized = require("fzf-lua.config").normalize_opts(
			vim.tbl_extend("force", options, { no_hide = true }),
			{}
		)
		assert.are.same(
			{ "ctrl-e", "ctrl-y", "enter" },
			vim.fn.sort(vim.tbl_keys(normalized.actions))
		)
		local before = vim.api.nvim_get_current_buf()
		normalized.actions.enter({ "not an entry" })
		assert.are.equal(before, vim.api.nvim_get_current_buf())
	end)

	it("refuses divergent operations instead of reconciling them during inspection", function()
		local base = jj("op", "log", "--no-graph", "--limit", "1", "-T", "id")
		jj("describe", "-m", "left operation")
		jj("--at-operation", base, "describe", "-m", "right operation")
		local heads_dir = repo .. "/.jj/repo/op_heads/heads"
		local before = vim.fn.sort(vim.fn.readdir(heads_dir))
		assert.are.equal(2, #before)
		local revisions, err = history.list(repo)
		assert.is_nil(revisions)
		assert.is_not_nil(err)
		assert.are.same(before, vim.fn.sort(vim.fn.readdir(heads_dir)))
	end)

	it("inspects hidden evolutionary versions and interdiffs without restoring them", function()
		vim.fn.writefile({ "second" }, repo .. "/file.txt")
		jj("describe", "-m", "before rewrite")
		local old_commit = jj("log", "--no-graph", "-r", "@", "-T", "commit_id")
		vim.fn.writefile({ "rewritten" }, repo .. "/file.txt")
		jj("describe", "-m", "after rewrite")
		local before =
			assert(history.run({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, repo))
		local versions = assert(history.list(repo, "@"))
		local old
		for _, version in ipairs(versions) do
			if version.commit_id == old_commit then
				old = version
			end
		end
		assert.is_not_nil(old)
		assert.matches("+second", assert(history.patch(repo, old)), 1, true)
		assert.matches("+after rewrite", assert(history.patch(repo, versions[1], "@")), 1, true)
		local content_step = false
		for _, version in ipairs(versions) do
			if assert(history.patch(repo, version, "@")):find("+rewritten", 1, true) then
				content_step = true
			end
		end
		assert.is_true(content_step)
		history.pick(repo, versions[1].commit_id)
		assert.are.equal("Previous drafts> ", options.prompt)
		assert.matches(versions[1].recorded_at, entries[1], 1, true)
		assert.matches("\t[selected]", entries[1], 1, true)
		assert.matches("\t[earlier]", entries[2], 1, true)
		assert.matches("Previous drafts of this change", options.fzf_opts["--header"], 1, true)
		assert.are.same(
			{ "ctrl-d", "ctrl-y", "enter" },
			vim.fn.sort(vim.tbl_keys(options.actions()))
		)
		options.actions().enter({ entries[1] })
		assert.is_false(vim.bo.modifiable)
		assert.matches(
			"-before rewrite",
			table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
			1,
			true
		)
		local draft = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.matches("Comparison: earlier draft(s) -> selected draft", draft, 1, true)
		assert.matches("Selected draft: " .. versions[1].commit_id, draft, 1, true)
		local predecessor = jj(
			"--ignore-working-copy",
			"evolog",
			"-r",
			versions[1].commit_id,
			"-n",
			"1",
			"--no-graph",
			"-T",
			'predecessors.map(|p| p.commit_id().short()).join(", ")'
		)
		assert.matches("Earlier draft(s): " .. predecessor, draft, 1, true)
		options.actions()["ctrl-d"]({ entries[1] })
		wait_overview()
		assert.matches("Pinned draft against parents", review_text(), 1, true)
		assert.is_nil(review_text():find("\nrewritten\n", 1, true))
		expand_file("file.txt", "\nrewritten\n")
		assert.are.equal(
			before,
			history.run({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, repo)
		)
	end)

	it(
		"opens the selected stack revision's evolution rather than defaulting to the workspace",
		function()
			history.pick_stack()
			for _, entry in ipairs(entries) do
				if entry:find(first_commit:sub(1, 12), 1, true) then
					options.actions()["ctrl-e"]({ entry })
					break
				end
			end
			assert.are.equal("Previous drafts> ", options.prompt)
			assert.matches(first_change, options.fzf_opts["--header"], 1, true)
			assert.matches(first_commit:sub(1, 12), entries[1], 1, true)
		end
	)

	it("labels the initial draft without inventing a previous comparison", function()
		local versions = assert(history.list(repo, first_commit))
		local initial = versions[#versions]
		local patch = assert(history.patch(repo, initial, first_commit))
		assert.matches("No earlier recorded draft to compare.", patch, 1, true)
		assert.matches("Selected draft: " .. initial.commit_id, patch, 1, true)
		assert.is_nil(patch:find("Comparison: earlier draft(s)", 1, true))
		assert.is_false(initial.has_predecessors)
		assert.is_nil(patch:find("diff --git", 1, true))
		assert.matches("Ctrl-D: complete patch against parents", patch, 1, true)
	end)

	it(
		"filters file history and patches with literal filesets, excluding unrelated changes",
		function()
			local path = 'space (all) | "quote" café.txt'
			vim.fn.writefile({ "target content" }, repo .. "/" .. path)
			vim.fn.writefile({ "unrelated content" }, repo .. "/other.txt")
			jj("describe", "-m", "file addition")
			local target = jj("log", "--no-graph", "-r", "@", "-T", "commit_id")
			jj("new", "-m", "unrelated revision")
			vim.fn.writefile({ "other modification" }, repo .. "/other.txt")
			jj("describe", "-m", "unrelated revision")
			local buffer = vim.fn.bufadd(repo .. "/" .. path)
			vim.fn.bufload(buffer)
			vim.api.nvim_win_set_buf(0, buffer)
			history.pick_file()
			assert.matches("JJ file ", options.prompt, 1, true)
			assert.are.equal(1, #entries)
			assert.matches(target:sub(1, 12), entries[1], 1, true)
			options.actions().enter({ entries[1] })
			wait_overview()
			assert.matches(path, vim.api.nvim_get_current_line(), 1, true)
			assert.is_nil(review_text():find("target content", 1, true))
			expand_file(path, "\ntarget content\n")
			assert.is_nil(review_text():find("unrelated content", 1, true))
			assert.is_false(vim.bo.modifiable)
			options.actions()["ctrl-e"]({ entries[1] })
			assert.are.equal("Previous drafts> ", options.prompt)
			assert.matches(target:sub(1, 12), entries[1], 1, true)
			options.actions()["ctrl-d"]({ entries[1] })
			wait_overview()
			assert.matches("Pinned draft against parents", review_text(), 1, true)
			expand_file("other.txt", "\nunrelated content\n")
		end
	)

	it("rejects unnamed file-history buffers without falling back to repository history", function()
		local notify, message = vim.notify
		vim.notify = function(value)
			message = value
		end
		vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))
		entries, options = nil, nil
		local ok, err = pcall(history.pick_file)
		vim.notify = notify
		assert(ok, err)
		assert.is_nil(entries)
		assert.matches("requires a named file buffer", message, 1, true)
	end)

	it("wires revision and file history without a standalone evolution mapping", function()
		local config = package.loaded["lib.config"]
		package.loaded["lib.config"] = {
			run = function(spec)
				if vim.tbl_contains(spec.plugins, "https://github.com/ibhagwan/fzf-lua") then
					spec.setup()
				end
			end,
		}
		local ok, err = pcall(dofile, "lua/config/git.lua")
		package.loaded["lib.config"] = config
		assert(ok, err)
		assert.are.equal(history.pick_stack, vim.fn.maparg("<leader>jl", "n", false, true).callback)
		assert.are.equal("", vim.fn.maparg("<leader>gdr", "n"))
		for _, key in ipairs({ "gdb", "gdl", "gds" }) do
			assert.are.equal("", vim.fn.maparg("<leader>" .. key, "n"))
		end
		assert.are.equal(
			require("lib.jj_review_source").pick_bookmark,
			vim.fn.maparg("<leader>jb", "n", false, true).callback
		)
		assert.are.equal(
			require("lib.jj_review_source").open_line,
			vim.fn.maparg("<leader>ja", "n", false, true).callback
		)
		assert.are.equal(
			require("lib.jj_review").resume,
			vim.fn.maparg("<leader>jr", "n", false, true).callback
		)
		assert.are.equal("function", type(vim.fn.maparg("<leader>jx", "n", false, true).callback))
		assert.are.equal("", vim.fn.maparg("<leader>je", "n"))
		assert.is_nil(history.pick_evolution)
		assert.are.equal(history.pick_file, vim.fn.maparg("<leader>jf", "n", false, true).callback)
		assert.are.equal(
			require("lib.git_history").pick_file,
			vim.fn.maparg("<leader>glf", "n", false, true).callback
		)
	end)

	it("encodes control characters using JJ fileset syntax rather than JSON escapes", function()
		for _, suffix in ipairs({ "\1", "\b", "\f", "\n", "\r", "\t", "\\", '"' }) do
			local path = "control" .. suffix .. "file.txt"
			vim.fn.writefile({ "literal bytes" }, repo .. "/" .. path)
			jj("describe", "-m", "literal path")
			local revisions, err = history.list(repo, nil, path)
			assert.is_not_nil(revisions, err)
			assert.are.equal(1, #revisions)
			local patch, patch_err = history.patch(repo, revisions[1], nil, path)
			assert.is_not_nil(patch, patch_err)
			assert.matches("+literal bytes", patch, 1, true)
		end
	end)

	it(
		"runs cancellable bounded async inspection without reconciling divergent operations",
		function()
			local worker = require("lib.jj_review_process")
			local function request(args, limit, should_cancel)
				local done, failure = false, nil
				local job = worker.start(repo, args, limit, function(err)
					failure = err
					done = true
				end)
				if should_cancel then
					job.cancel()
				end
				assert.is_true(vim.wait(5000, function()
					return done
				end))
				return job, failure
			end
			local job, failure = request({ "log", "--no-graph", "-n", "1", "-T", '"12345678"' }, 4)
			assert.matches("limit", failure, 1, true)
			vim.fn.delete(job.path)
			local spawn = vim.uv.spawn
			vim.uv.spawn = function(command, opts, callback)
				return spawn(command, opts, function()
					callback(0, 15)
				end)
			end
			local ok, signalled, signal_err = pcall(request, { "log" }, 100000)
			vim.uv.spawn = spawn
			assert(ok, signalled)
			assert.matches("signal 15", signal_err, 1, true)
			vim.fn.delete(signalled.path)
			job, failure = request({ "log" }, 100000, true)
			assert.matches("Cancelled", failure, 1, true)
			assert.is_nil(vim.uv.fs_stat(job.path))
			local base = jj("op", "log", "--no-graph", "--limit", "1", "-T", "id")
			jj("describe", "-m", "left")
			jj("--at-operation", base, "describe", "-m", "right")
			local heads = vim.fn.sort(vim.fn.readdir(repo .. "/.jj/repo/op_heads/heads"))
			job, failure = request({ "log" }, 100000)
			assert.is_not_nil(failure)
			assert.are.same(heads, vim.fn.sort(vim.fn.readdir(repo .. "/.jj/repo/op_heads/heads")))
			vim.fn.delete(job.path)
		end
	)

	it("loads a real 100k-line patch lazily using bounded rendered pages and refreshes", function()
		local lines = {}
		for index = 1, 100005 do
			lines[index] = "large line " .. index
		end
		local path = 'large "quote" \\ \1.txt'
		vim.fn.writefile(lines, repo .. "/" .. path)
		jj("--config", "snapshot.max-new-file-size=10485760", "describe", "-m", "large revision")
		local revision = assert(history.list(repo))[1]
		local review = require("lib.jj_review")
		local buffer = review.open(repo, revision)
		local function content()
			return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
		end
		assert.is_true(
			vim.wait(5000, function()
				return content():find("not loaded", 1, true) ~= nil
			end),
			content()
		)
		assert.is_true(vim.api.nvim_buf_line_count(buffer) < 20)
		vim.fn.maparg("]f", "n", false, true).callback()
		review.toggle(buffer)
		assert.is_true(
			vim.wait(5000, function()
				return content():find("large line 1", 1, true) ~= nil
			end),
			content()
		)
		assert.is_true(vim.api.nvim_buf_line_count(buffer) < 420)
		review.turn_page(buffer, 1)
		assert.matches("Page 2", content(), 1, true)
		jj("describe", "-m", "refreshed revision")
		review.refresh(buffer)
		assert.is_true(
			vim.wait(5000, function()
				return content():find("not loaded", 1, true) ~= nil
			end),
			content()
		)
		assert.matches("refreshed revision", content(), 1, true)
		assert.is_true(vim.api.nvim_buf_line_count(buffer) < 20)
	end)

	it(
		"refuses unsafe working-copy jumps until disk and buffer match a recorded snapshot",
		function()
			local revision
			for _, item in ipairs(assert(history.list(repo))) do
				if item.commit_id == first_commit then
					revision = item
				end
			end
			local review = require("lib.jj_review")
			local buffer = review.open(repo, revision)
			local function content()
				return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
			end
			assert.is_true(vim.wait(5000, function()
				return content():find("not loaded", 1, true) ~= nil
			end))
			vim.fn.maparg("]f", "n", false, true).callback()
			review.toggle(buffer)
			assert.is_true(vim.wait(5000, function()
				return content():find("\nfirst\n", 1, true) ~= nil
			end))
			for row, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
				if line == "first" then
					vim.api.nvim_win_set_cursor(0, { row, 0 })
					break
				end
			end
			local messages = {}
			vim.notify = function(message)
				messages[#messages + 1] = message
			end
			vim.fn.writefile({ "inserted", "first" }, repo .. "/file.txt")
			vim.fn.maparg("gf", "n", false, true).callback()
			assert.is_true(vim.wait(5000, function()
				return #messages > 0
			end))
			assert.matches("Working file differs", messages[1], 1, true)
			assert.are.equal(buffer, vim.api.nvim_get_current_buf())
			jj("describe", "-m", "record edit")
			local before =
				assert(history.run({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, repo))
			messages = {}
			vim.fn.maparg("gf", "n", false, true).callback()
			assert.is_true(vim.wait(5000, function()
				return #messages > 0
			end))
			assert.matches("Buffer differs", messages[1], 1, true)
			assert.are.equal(buffer, vim.api.nvim_get_current_buf())
			vim.api.nvim_buf_call(vim.fn.bufnr(repo .. "/file.txt"), function()
				vim.cmd("edit!")
			end)
			vim.fn.maparg("gf", "n", false, true).callback()
			assert.is_true(vim.wait(5000, function()
				return vim.api.nvim_get_current_buf() ~= buffer
			end))
			assert.are.equal("first", vim.api.nvim_get_current_line())
			assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
			assert.are.equal(
				before,
				history.run({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, repo)
			)
		end
	)

	it("reports an unavailable JJ executable without breaking Git-only inspection", function()
		local system = vim.system
		vim.system = function()
			error("jj executable unavailable")
		end
		local ok, output, err = pcall(history.run, { "root" }, repo)
		vim.system = system
		assert.is_true(ok)
		assert.is_nil(output)
		assert.matches("JJ unavailable", err, 1, true)
		assert.matches("glh / glf / gbl / gbf", err, 1, true)
	end)

	it("reports malformed data and command failures without opening a picker", function()
		local run = history.run
		history.run = function()
			return "not json"
		end
		local result, err = history.list(repo)
		history.run = run
		assert.is_nil(result)
		assert.matches("invalid history data", err, 1, true)
		local output, command_err = history.run({ "log" }, directory)
		assert.is_nil(output)
		assert.is_not_nil(command_err)
	end)
end)
