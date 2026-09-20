local history = require("lib.git_history")
local fzf = require("fzf-lua")
local config = require("fzf-lua.config")

describe("read-only Git history", function()
	local directory, original_buf, original_win, first_commit

	local function git(...)
		local command = {
			"git",
			"-C",
			directory,
			"-c",
			"user.name=History Test",
			"-c",
			"user.email=history@example.invalid",
			"-c",
			"commit.gpgsign=false",
			"-c",
			"core.hooksPath=/dev/null",
			...,
		}
		local result = vim.system(command, {
			text = true,
			env = {
				GIT_CONFIG_NOSYSTEM = "1",
				GIT_CONFIG_GLOBAL = "/dev/null",
			},
		}):wait()
		assert.are.equal(0, result.code, result.stderr)
		return vim.trim(result.stdout)
	end

	before_each(function()
		directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		directory = assert(vim.uv.fs_realpath(directory))
		original_buf, original_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
		git("init", "--quiet")
		vim.fn.writefile({ "original content" }, directory .. "/old name.txt")
		git("add", "--", "old name.txt")
		git("commit", "--quiet", "-m", "original")
		first_commit = git("rev-parse", "HEAD")
		git("mv", "old name.txt", "new name.txt")
		git("commit", "--quiet", "-m", "rename")
		vim.api.nvim_win_set_buf(original_win, vim.api.nvim_create_buf(true, false))
		vim.cmd.edit(directory .. "/new name.txt")
		fzf.setup({ git = history.options(fzf) })
	end)

	after_each(function()
		vim.api.nvim_set_current_win(original_win)
		vim.api.nvim_win_set_buf(original_win, original_buf)
		vim.cmd("silent! only")
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if buf ~= original_buf then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.fn.delete(directory, "rf")
	end)

	it("replaces all default history actions after real fzf-lua normalization", function()
		for _, name in ipairs({ "commits", "reflog" }) do
			local opts = config.normalize_opts({ no_hide = true }, "git." .. name)
			assert.are.same({ "ctrl-y", "enter" }, vim.fn.sort(vim.tbl_keys(opts.actions)))
			assert.are.equal(history.show_commit, opts.actions.enter)
			assert.are.equal(fzf.actions.git_yank_commit, opts.actions["ctrl-y"])
		end
		local opts = config.normalize_opts({ no_hide = true }, "git.bcommits")
		assert.is_true(opts.follow)
		assert.are.same(history.options(fzf).bcommits.actions(), opts.actions)
	end)

	it("installs the same allowlists through the actual search configuration", function()
		local add = vim.pack.add
		vim.pack.add = function() end
		local ok, err = pcall(dofile, "lua/config/search.lua")
		vim.pack.add = add
		assert(ok, err)
		local opts = config.normalize_opts({}, "git.commits")
		assert.are.same({ "ctrl-y", "enter", "esc" }, vim.fn.sort(vim.tbl_keys(opts.actions)))
		assert.are.equal(history.show_commit, config.globals.git.commits.actions().enter)
		assert.is_nil(config.normalize_opts({}, "git.reflog").actions["ctrl-d"])
	end)

	it("opens a commit patch without changing HEAD, index or worktree", function()
		local head, status, index =
			git("rev-parse", "HEAD"), git("status", "--porcelain"), git("write-tree")
		history.show_commit({ first_commit .. " original" }, { cwd = directory })
		assert.is_false(vim.bo.modifiable)
		assert.is_true(vim.bo.readonly)
		assert.are.equal("nofile", vim.bo.buftype)
		assert.matches(
			"original content",
			table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
			1,
			true
		)
		assert.are.equal(head, git("rev-parse", "HEAD"))
		assert.are.equal(status, git("status", "--porcelain"))
		assert.are.equal(index, git("write-tree"))
	end)

	it("follows renames and opens the old filename at the selected commit", function()
		local core = require("fzf-lua.core")
		local exec = core.fzf_exec
		local entries, options
		core.fzf_exec = function(items, opts)
			entries, options = items, opts
		end
		local ok, err = pcall(history.pick_file)
		core.fzf_exec = exec
		assert(ok, err)
		assert.are.equal(directory, options.cwd)
		local selected
		for _, entry in ipairs(entries) do
			if options.fn_match_file(entry) == "old name.txt" then
				selected = entry
			end
		end
		assert.is_not_nil(selected)
		options.actions.enter.fn({ selected }, options)
		assert.are.same({ "original content", "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		assert.is_false(vim.bo.modifiable)
		assert.are.equal("nofile", vim.bo.buftype)
		assert.are.equal("", git("status", "--porcelain"))
	end)

	it("decodes Git-quoted paths for both historical files and previews", function()
		for _, suffix in ipairs({ '"quote.txt', "\\123.txt", "\tname.txt", "\nname.txt" }) do
			local old, new = "old" .. suffix, "new" .. suffix
			vim.fn.writefile({ "quoted content" }, directory .. "/" .. old)
			git("add", "--", old)
			git("commit", "--quiet", "-m", "quoted file")
			git("mv", old, new)
			git("commit", "--quiet", "-m", "rename quoted file")
			local source = vim.fn.bufadd(directory .. "/" .. new)
			vim.fn.bufload(source)
			vim.api.nvim_win_set_buf(0, source)
			local core = require("fzf-lua.core")
			local exec, entries, options = core.fzf_exec
			core.fzf_exec = function(items, opts)
				entries, options = items, opts
			end
			local ok, err = pcall(history.pick_file)
			core.fzf_exec = exec
			assert(ok, err)
			local selected
			for _, entry in ipairs(entries) do
				if options.fn_match_file(entry, options) == old then
					selected = entry
				end
			end
			assert.is_not_nil(selected, vim.inspect({ suffix, entries }))
			local preview = vim.api.nvim_create_buf(false, true)
			local class = history.options(fzf).bcommits.previewer()._ctor()
			class.populate_preview_buf({
				opts = options,
				get_tmp_buffer = function()
					return preview
				end,
				set_preview_buf = function() end,
			}, selected)
			assert.matches(
				"+quoted content",
				table.concat(vim.api.nvim_buf_get_lines(preview, 0, -1, false), "\n"),
				1,
				true
			)
			vim.api.nvim_buf_delete(preview, { force = true })
			options.actions.enter.fn({ selected }, options)
			assert.are.equal("quoted content", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		end
	end)

	it("uses the buffer repository rather than the editor cwd", function()
		local pick = fzf.git_commits
		local options
		fzf.git_commits = function(opts)
			options = opts
		end
		local ok, err = pcall(history.pick_repository)
		fzf.git_commits = pick
		assert(ok, err)
		assert.are.equal(directory, options.cwd)
	end)

	it("rejects invalid selections without opening a buffer", function()
		local notify, messages = vim.notify, {}
		vim.notify = function(message)
			table.insert(messages, message)
		end
		local buf = vim.api.nvim_get_current_buf()
		local ok, err = pcall(function()
			history.show_commit({}, { cwd = directory })
			history.show_commit({ "--bad-option" }, { cwd = directory })
		end)
		vim.notify = notify
		assert(ok, err)
		assert.are.equal(buf, vim.api.nvim_get_current_buf())
		assert.are.equal(1, #messages)
	end)
end)
