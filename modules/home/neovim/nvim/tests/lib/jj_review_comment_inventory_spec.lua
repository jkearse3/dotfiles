local inventory = require("lib.jj_review_comment_inventory")
local review_comments = require("lib.jj_review_comments")

describe("JJ review comment inventory", function()
	local directory, repo, config, original_store, original_confirm, original_notify
	local landed, open, gone
	local unreadable = string.rep("y", 32)
	local function command(args)
		local result = vim.system(args, { cwd = repo, text = true }):wait()
		assert.are.equal(0, result.code, result.stderr)
		return vim.trim(result.stdout)
	end
	local function jj(...)
		return command({ "jj", "--no-pager", "--color", "never", ... })
	end
	local function change_id()
		return jj("log", "--no-graph", "-r", "@", "-T", "change_id")
	end
	local function comment_on(change)
		assert.is_nil(review_comments.save(repo, change, {
			{
				id = "c",
				path = "file.txt",
				commit_id = "0",
				lines = { { side = "new", kind = "add", line = 1, text = "x" } },
				body = "Note",
			},
		}))
	end
	local function stored(change)
		return vim.uv.fs_stat(review_comments.store_path(repo, change)) ~= nil
	end
	local function states()
		local result = {}
		for _, entry in ipairs(assert(inventory.list(repo))) do
			result[#result + 1] = entry.state .. ":" .. entry.change_id
		end
		return result
	end

	before_each(function()
		directory = vim.fn.tempname()
		repo = directory .. "/repo"
		vim.fn.mkdir(repo, "p")
		repo = assert(vim.uv.fs_realpath(repo))
		config = vim.env.JJ_CONFIG
		vim.env.JJ_CONFIG = directory .. "/jj.toml"
		vim.fn.writefile({
			"[user]",
			'name = "Review Test"',
			'email = "test@example.invalid"',
			"[revset-aliases]",
			"'immutable_heads()' = 'bookmarks(exact:\"trunk\")'",
		}, vim.env.JJ_CONFIG)
		original_store = review_comments.store_directory
		review_comments.store_directory = function()
			return directory .. "/comments"
		end
		original_confirm, original_notify = vim.fn.confirm, vim.notify
		vim.notify = function() end

		command({ "git", "init", "--quiet" })
		command({ "jjx", "ensure" })
		vim.fn.writefile({ "x" }, repo .. "/file.txt")
		jj("describe", "-m", "landed")
		landed = change_id()
		jj("bookmark", "create", "trunk", "-r", "@")
		jj("new", "-m", "abandoned")
		gone = change_id()
		jj("abandon", "@")
		jj("describe", "-m", "open")
		open = change_id()

		for _, change in ipairs({ landed, open, gone }) do
			comment_on(change)
		end
		vim.fn.mkdir(vim.fs.dirname(review_comments.store_path(repo, unreadable)), "p")
		vim.fn.writefile({ "not json" }, review_comments.store_path(repo, unreadable))
	end)

	after_each(function()
		review_comments.store_directory = original_store
		vim.fn.confirm, vim.notify = original_confirm, original_notify
		vim.env.JJ_CONFIG = config
		vim.fn.delete(directory, "rf")
	end)

	it("classifies commented changes in log order with vanished changes last", function()
		assert.are.same({
			"open:" .. open,
			"landed:" .. landed,
			"gone:" .. gone,
			"unreadable:" .. unreadable,
		}, states())
	end)

	it(
		"prunes gone changes by default and landed changes on request, after confirmation",
		function()
			local questions = {}
			vim.fn.confirm = function(question)
				questions[#questions + 1] = question
				return 2
			end
			inventory.prune(repo)
			assert.is_true(stored(gone))
			assert.matches("[gone]", questions[1], 1, true)

			vim.fn.confirm = function()
				return 1
			end
			inventory.prune(repo)
			assert.is_false(stored(gone))
			assert.is_true(stored(landed))

			inventory.prune(repo, true)
			assert.is_false(stored(landed))
			assert.is_true(stored(open))
			assert.are.same({ "open:" .. open, "unreadable:" .. unreadable }, states())
		end
	)

	it("deletes a change's comments from the picker and reopens it", function()
		local fzf = require("fzf-lua")
		local original_exec, calls = fzf.fzf_exec, {}
		fzf.fzf_exec = function(lines, opts)
			calls[#calls + 1] = { lines = lines, opts = opts }
		end
		vim.fn.confirm = function()
			return 1
		end
		local ok, err = pcall(function()
			inventory.pick(repo)
			local line = calls[1].lines[3]
			assert.matches("[gone]", line, 1, true)
			assert.matches("1 comment  (change no longer exists)", line, 1, true)
			calls[1].opts.actions()["ctrl-x"]({ line })
		end)
		fzf.fzf_exec = original_exec
		assert(ok, err)
		assert.is_false(stored(gone))
		assert.are.equal(2, #calls)
		assert.are.equal(3, #calls[2].lines)
	end)
end)
