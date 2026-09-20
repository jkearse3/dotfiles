local permalink = require("lib.git_permalink")

describe("GitHub remote URLs", function()
	it("accepts HTTPS, SCP-style SSH, and SSH URLs without retaining credentials", function()
		for _, remote in ipairs({
			"https://github.com/owner/repo.git",
			"https://user:secret@github.com/owner/repo",
			"git@github.com:owner/repo.git",
			"ssh://git@github.com/owner/repo.git",
			"ssh://git@ssh.github.com:443/owner/repo.git",
		}) do
			assert.are.equal("https://github.com/owner/repo", permalink.remote_base(remote))
		end
	end)

	it("requires explicit opt-in for GitHub Enterprise hosts", function()
		assert.is_nil(permalink.remote_base("git@git.example.com:owner/repo.git"))
		assert.are.equal(
			"https://git.example.com/owner/repo",
			permalink.remote_base(
				"git@git.example.com:owner/repo.git",
				{ "https://git.example.com" }
			)
		)
	end)

	it(
		"preserves explicitly configured Enterprise HTTPS ports for SSH and HTTPS remotes",
		function()
			for _, remote in ipairs({
				"ssh://git@git.example.com/owner/repo.git",
				"https://git.example.com:8443/owner/repo.git",
			}) do
				assert.are.equal(
					"https://git.example.com:8443/owner/repo",
					permalink.remote_base(remote, { "https://git.example.com:8443" })
				)
			end
		end
	)

	it("rejects unsupported transports, providers and malformed repository paths", function()
		for _, remote in ipairs({
			"/local/repo",
			"file:///repo",
			"git@gitlab.com:owner/repo.git",
			"https://github.com/owner",
			"https://github.com/owner/repo?query=1",
		}) do
			assert.is_nil(permalink.remote_base(remote))
		end
	end)
end)

describe("commit-pinned permalinks", function()
	local directory, buf, original_buf, commit, path, original_notify, original_setreg
	local function git(...)
		local result = vim.system({
			"git",
			"-C",
			directory,
			"-c",
			"user.name=Permalink Test",
			"-c",
			"user.email=permalink@example.invalid",
			"-c",
			"commit.gpgsign=false",
			"-c",
			"core.hooksPath=/dev/null",
			...,
		}, {
			text = true,
			env = {
				GIT_CONFIG_NOSYSTEM = "1",
				GIT_CONFIG_GLOBAL = "/dev/null",
			},
		}):wait()
		assert.are.equal(0, result.code, result.stderr)
		return vim.trim(result.stdout)
	end

	local function load_file(filename)
		buf = vim.fn.bufadd(filename)
		vim.fn.bufload(buf)
		vim.api.nvim_win_set_buf(0, buf)
	end

	before_each(function()
		original_buf = vim.api.nvim_get_current_buf()
		original_notify, original_setreg = vim.notify, vim.fn.setreg
		directory = vim.fn.tempname()
		vim.fn.mkdir(directory .. "/src", "p")
		directory = assert(vim.uv.fs_realpath(directory))
		path = 'src/space # % quote" café.lua'
		vim.fn.writefile({ "one", "two", "three" }, directory .. "/" .. path)
		git("init", "--quiet", "--initial-branch=main")
		git("add", "--", path)
		git("commit", "--quiet", "-m", "initial")
		commit = git("rev-parse", "HEAD")
		git("remote", "add", "origin", "https://github.com/owner/repo.git")
		git("update-ref", "refs/remotes/origin/main", commit)
		load_file(directory .. "/" .. path)
	end)

	after_each(function()
		vim.notify, vim.fn.setreg = original_notify, original_setreg
		vim.api.nvim_win_set_buf(0, original_buf)
		for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
			if buffer ~= original_buf then
				vim.api.nvim_buf_delete(buffer, { force = true })
			end
		end
		vim.fn.delete(directory, "rf")
	end)

	it("pins and encodes single lines and reversed ranges in the buffer repository", function()
		local prefix = "https://github.com/owner/repo/blob/"
			.. commit
			.. "/src/space%20%23%20%25%20quote%22%20caf%C3%A9.lua?plain=1"
		assert.are.equal(prefix .. "#L2", permalink.build(buf, 2, 2))
		assert.are.equal(prefix .. "#L1-L3", permalink.build(buf, 3, 1))
	end)

	it("prefers the configured upstream remote over origin", function()
		git("remote", "add", "upstream", "git@github.com:upstream/repo.git")
		git("update-ref", "refs/remotes/upstream/main", commit)
		git("config", "branch.main.remote", "upstream")
		git("config", "branch.main.merge", "refs/heads/main")
		assert.matches(
			"https://github.com/upstream/repo/",
			assert(permalink.build(buf, 1, 1)),
			1,
			true
		)
	end)

	it("supports detached HEAD and linked worktrees", function()
		local worktree = directory .. "/linked"
		git("worktree", "add", "--quiet", "--detach", worktree, commit)
		load_file(worktree .. "/" .. path)
		assert.matches("/blob/" .. commit .. "/", assert(permalink.build(buf, 1, 1)), 1, true)
	end)

	it("accepts a sole remote but refuses ambiguous forks", function()
		git("remote", "rename", "origin", "fork")
		assert.is_not_nil(permalink.build(buf, 1, 1))
		git("remote", "add", "other", "git@github.com:other/repo.git")
		local url, err = permalink.build(buf, 1, 1)
		assert.is_nil(url)
		assert.matches("No unambiguous remote", err, 1, true)
	end)

	it("refuses a commit not reachable from the chosen remote's cached refs", function()
		git("commit", "--quiet", "--allow-empty", "-m", "unpublished")
		local url, err = permalink.build(buf, 1, 1)
		assert.is_nil(url)
		assert.matches("HEAD is not present", err, 1, true)
	end)

	it("refuses unsaved, unstaged, and staged changes", function()
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "changed" })
		assert.is_nil(permalink.build(buf, 1, 1))
		vim.bo[buf].modified = false
		vim.fn.writefile({ "changed", "two", "three" }, directory .. "/" .. path)
		local url, err = permalink.build(buf, 1, 1)
		assert.is_nil(url)
		assert.matches("File differs from HEAD", err, 1, true)
		git("add", "--", path)
		assert.is_nil(permalink.build(buf, 1, 1))
	end)

	it("refuses staged changes even when the worktree was changed back to HEAD", function()
		vim.fn.writefile({ "staged", "two", "three" }, directory .. "/" .. path)
		git("add", "--", path)
		vim.fn.writefile({ "one", "two", "three" }, directory .. "/" .. path)
		local url, err = permalink.build(buf, 1, 1)
		assert.is_nil(url)
		assert.matches("File differs from HEAD", err, 1, true)
	end)

	it("handles CRLF, UTF-8 BOMs and missing final newlines without shifting lines", function()
		for _, content in ipairs({
			"one\r\ntwo\r\n",
			"one\ntwo",
			"\239\187\191one\ntwo\n",
			"\239\187\191one\r\ntwo\r\n",
		}) do
			local filename = directory .. "/endings.txt"
			vim.fn.writefile(vim.split(content, "\n", { plain = true }), filename, "b")
			git("add", "--", "endings.txt")
			git("commit", "--quiet", "-m", "line endings")
			git("update-ref", "refs/remotes/origin/main", git("rev-parse", "HEAD"))
			load_file(filename)
			vim.api.nvim_buf_call(buf, function()
				vim.cmd("edit!")
			end)
			local url, err = permalink.build(buf, 2, 2)
			assert.is_not_nil(url, err)
			assert.matches("#L2", url, 1, true)
		end
	end)

	it("refuses a stale unmodified buffer even when the worktree matches HEAD", function()
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "stale" })
		vim.bo[buf].modified = false
		local url, err = permalink.build(buf, 1, 1)
		assert.is_nil(url)
		assert.matches("Buffer contents do not match HEAD", err, 1, true)
	end)

	it("refuses untracked, unnamed, and non-file buffers and invalid line ranges", function()
		assert.is_nil(permalink.build(buf, 0, 1))
		assert.is_nil(permalink.build(buf, 1, 4))
		vim.bo[buf].buftype = "nofile"
		assert.is_nil(permalink.build(buf, 1, 1))
		vim.fn.writefile({ "untracked" }, directory .. "/new.lua")
		load_file(directory .. "/new.lua")
		assert.is_nil(permalink.build(buf, 1, 1))
		local unnamed = vim.api.nvim_create_buf(false, true)
		assert.is_nil(permalink.build(unnamed, 1, 1))
	end)

	it("keeps the clipboard unchanged on failure and copies on success", function()
		local copied, messages = "existing clipboard", {}
		vim.fn.setreg = function(register, value)
			assert.are.equal("+", register)
			copied = value
		end
		vim.notify = function(message)
			table.insert(messages, message)
		end
		permalink.copy(1, 10)
		assert.are.equal("existing clipboard", copied)
		permalink.copy(1, 1)
		assert.matches("https://github.com/owner/repo/blob/", copied, 1, true)
		assert.are.equal(2, #messages)
	end)

	it("reads current visual selection rather than stale visual marks", function()
		local runner = package.loaded["lib.config"]
		package.loaded["lib.config"] = { run = function() end }
		local ok, err = pcall(dofile, "lua/config/git.lua")
		package.loaded["lib.config"] = runner
		assert(ok, err)
		local copied
		vim.fn.setreg = function(_, value)
			copied = value
		end
		vim.notify = function() end
		vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
		vim.api.nvim_buf_set_mark(buf, ">", 1, 0, {})
		vim.api.nvim_win_set_cursor(0, { 3, 0 })
		vim.cmd("normal! Vkk")
		vim.fn.maparg("<leader>gy", "x", false, true).callback()
		vim.cmd("normal! \27")
		assert.matches("#L1-L3", copied, 1, true)
	end)
end)
