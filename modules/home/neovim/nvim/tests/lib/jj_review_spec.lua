local review = require("lib.jj_review")
local process = require("lib.jj_review_process")
local page = require("lib.jj_review_page")

local function write_raw(path, content)
	local fd = assert(vim.uv.fs_open(path, "w", 384))
	assert(vim.uv.fs_write(fd, content, 0))
	vim.uv.fs_close(fd)
end

local function patch(count)
	local lines = {
		"diff --git a/a.lua b/a.lua",
		"new file mode 100644",
		"--- /dev/null",
		"+++ b/a.lua",
		"@@ -0,0 +1," .. count .. " @@",
	}
	for i = 1, count do
		lines[#lines + 1] = "+line " .. i
	end
	return table.concat(lines, "\n") .. "\n"
end

describe("lazy JJ review", function()
	local directory, original_start, original_buf, original_win, requests, buffer
	local revision = {
		commit_id = string.rep("a", 40),
		change_id = string.rep("k", 32),
		description = "Review revision",
	}
	local function contents()
		return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
	end
	local function row(label)
		for number, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
			if line:find(label, 1, true) then
				return number
			end
		end
		error("Missing row: " .. label .. "\n" .. contents())
	end
	local function select_file(path)
		vim.api.nvim_win_set_cursor(0, { row("M " .. path .. "  ("), 0 })
	end
	local function finish(number, output, err)
		local request = requests[number]
		write_raw(request.job.path, output or "")
		request.complete(err)
	end
	local function files(paths)
		local lines = {}
		for _, path in ipairs(paths) do
			lines[#lines + 1] = vim.json.encode({ path = path, display = path, status = "M" })
		end
		return table.concat(lines, "\n") .. "\n"
	end

	before_each(function()
		directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		original_buf, original_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
		original_start = process.start
		requests = {}
		process.start = function(repo, args, limit, complete)
			local job = { path = directory .. "/" .. (#requests + 1), cancel = function() end }
			job.cancel = function()
				job.cancelled = true
			end
			requests[#requests + 1] =
				{ repo = repo, args = args, limit = limit, complete = complete, job = job }
			return job
		end
		buffer = review.open(directory, revision)
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(buffer) then
			vim.api.nvim_buf_delete(buffer, { force = true })
		end
		process.start = original_start
		vim.api.nvim_set_current_win(original_win)
		vim.api.nvim_win_set_buf(original_win, original_buf)
		vim.fn.delete(directory, "rf")
	end)

	it(
		"opens only metadata and navigates collapsed file headers without fetching patches",
		function()
			assert.are.equal(1, #requests)
			assert.is_true(vim.tbl_contains(requests[1].args, "-T"))
			assert.is_false(vim.tbl_contains(requests[1].args, "--git"))
			finish(1, files({ "a.lua", "b.lua" }))
			assert.matches("2 changed files", contents(), 1, true)
			select_file("a.lua")
			vim.fn.maparg("]f", "n", false, true).callback()
			assert.are.equal(row("M b.lua"), vim.api.nvim_win_get_cursor(0)[1])
			local select = vim.ui.select
			vim.ui.select = function(items, _, callback)
				callback(items[1])
			end
			local ok, err = pcall(review.pick_file, buffer)
			vim.ui.select = select
			assert(ok, err)
			assert.are.equal(row("M a.lua"), vim.api.nvim_win_get_cursor(0)[1])
			assert.are.equal(1, #requests)
			assert.is_false(vim.bo[buffer].modifiable)
			assert.is_true(vim.bo[buffer].readonly)
		end
	)

	it("expands explicitly, pages a 100k-line file, and reopens from cache", function()
		finish(1, files({ "a.lua", "b.lua" }))
		select_file("a.lua")
		review.toggle(buffer)
		assert.are.equal(2, #requests)
		assert.is_true(vim.tbl_contains(requests[2].args, "--git"))
		finish(2, patch(100005))
		assert.matches("line 1", contents(), 1, true)
		assert.is_true(vim.api.nvim_buf_line_count(buffer) < 420)
		review.turn_page(buffer, 1)
		assert.matches("Page 2", contents(), 1, true)
		assert.is_nil(contents():find("\nline 1\n", 1, true))
		review.turn_page(buffer, -1)
		assert.matches("\nline 1\n", contents(), 1, true)
		review.toggle(buffer)
		assert.is_nil(contents():find("\nline 1\n", 1, true))
		review.toggle(buffer)
		assert.matches("\nline 1\n", contents(), 1, true)
		assert.are.equal(2, #requests)
		assert.is_true(vim.api.nvim_buf_line_count(buffer) < 420)
	end)

	it("ignores cancelled callbacks and cleans caches on replacement and deletion", function()
		finish(1, files({ "a.lua" }))
		select_file("a.lua")
		review.toggle(buffer)
		review.toggle(buffer)
		assert.is_true(requests[2].job.cancelled)
		review.toggle(buffer)
		finish(2, patch(1))
		assert.is_nil(contents():find("\nline 1\n", 1, true))
		assert.is_nil(vim.uv.fs_stat(requests[2].job.path))
		finish(3, patch(2))
		assert.is_not_nil(vim.uv.fs_stat(requests[3].job.path))
		assert.are.equal(buffer, review.open(directory, revision))
		assert.is_nil(vim.uv.fs_stat(requests[3].job.path))
		assert.is_nil(contents():find("\nline 2\n", 1, true))
		vim.api.nvim_buf_delete(buffer, { force = true })
		assert.is_true(requests[4].job.cancelled)
		finish(4, files({ "late.lua" }))
		assert.is_nil(vim.uv.fs_stat(requests[4].job.path))
	end)

	it("refreshes to the latest change version while invalidating cached patches", function()
		finish(1, files({ "a.lua" }))
		select_file("a.lua")
		review.toggle(buffer)
		finish(2, patch(2))
		review.refresh(buffer)
		assert.is_not_nil(vim.uv.fs_stat(requests[2].job.path))
		finish(3, string.rep("c", 128))
		local newer = vim.tbl_extend(
			"force",
			revision,
			{ commit_id = string.rep("b", 40), description = "Updated" }
		)
		finish(4, vim.json.encode(newer))
		assert.is_nil(vim.uv.fs_stat(requests[2].job.path))
		assert.is_true(vim.tbl_contains(requests[5].args, newer.commit_id))
		finish(5, files({ "b.lua" }))
		assert.matches("Updated", contents(), 1, true)
		assert.is_nil(contents():find("M a.lua", 1, true))
		assert.matches("not loaded", contents(), 1, true)
		assert.are.equal(5, #requests)
	end)

	it("keeps the pinned view and cached patches when refresh fails", function()
		finish(1, files({ "a.lua" }))
		select_file("a.lua")
		review.toggle(buffer)
		finish(2, patch(2))
		review.refresh(buffer)
		finish(3, string.rep("c", 128))
		finish(4, "", "ambiguous source")
		assert.matches("Refresh failed; retained pinned comparison", contents(), 1, true)
		assert.matches("line 1", contents(), 1, true)
		assert.is_not_nil(vim.uv.fs_stat(requests[2].job.path))
	end)

	it(
		"uses the same immutable range for metadata and explicit expansion and resumes without loading",
		function()
			buffer = review.open_comparison(directory, {
				revision = revision,
				from = string.rep("b", 40),
				title = "base -> feature (nearest first-parent bookmark)",
				source = { kind = "bookmark", name = "feature" },
				focus = { path = "b.lua", line = 20 },
			})
			assert.are.same(
				{ "diff", "--from", string.rep("b", 40), "--to", revision.commit_id },
				vim.list_slice(requests[2].args, 1, 5)
			)
			finish(2, files({ "a.lua", "b.lua" }))
			assert.are.equal(row("M b.lua"), vim.api.nvim_win_get_cursor(0)[1])
			assert.are.equal(2, #requests)
			assert.matches("base -> feature", contents(), 1, true)
			review.toggle(buffer)
			assert.is_true(vim.tbl_contains(requests[3].args, "--from"))
			assert.is_true(vim.tbl_contains(requests[3].args, string.rep("b", 40)))
			finish(3, patch(2))
			vim.api.nvim_set_current_buf(original_buf)
			review.resume()
			assert.are.equal(buffer, vim.api.nvim_get_current_buf())
			assert.are.equal(3, #requests)
		end
	)

	it("reports failures without displaying partial patches and can retry", function()
		finish(1, files({ "a.lua" }))
		select_file("a.lua")
		review.toggle(buffer)
		finish(2, patch(10), "JJ failed")
		assert.matches("JJ failed", contents(), 1, true)
		assert.is_nil(contents():find("\nline 1\n", 1, true))
		assert.is_nil(vim.uv.fs_stat(requests[2].job.path))
		review.toggle(buffer)
		review.toggle(buffer)
		finish(3, patch(1))
		assert.matches("\nline 1\n", contents(), 1, true)
	end)

	it("recreates an evicted quickfix index without losing unrelated quickfix lists", function()
		finish(1, files({ "a.lua" }))
		local old_id = vim.fn.getqflist({ id = 0 }).id
		for index = 1, 12 do
			vim.fn.setqflist({}, " ", { title = "Other " .. index, items = {} })
		end
		assert.are.equal(0, vim.fn.getqflist({ id = old_id }).id)
		local unrelated = vim.fn.getqflist({ id = 0 }).id
		select_file("a.lua")
		review.toggle(buffer)
		finish(2, patch(2))
		local current = vim.fn.getqflist({ id = 0, items = 0 })
		assert.is_true(current.id ~= old_id)
		assert.are.equal(buffer, current.items[1].bufnr)
		assert.are.equal(row("M a.lua"), current.items[1].lnum)
		assert.are.equal(unrelated, vim.fn.getqflist({ id = unrelated }).id)
	end)

	it("treats paging as recent use when choosing which expanded file to collapse", function()
		local paths = {}
		for index = 1, 9 do
			paths[index] = "file" .. index .. ".lua"
		end
		finish(1, files(paths))
		for index = 1, 8 do
			select_file(paths[index])
			review.toggle(buffer)
			finish(#requests, patch(450))
		end
		select_file(paths[1])
		review.turn_page(buffer, 1)
		select_file(paths[9])
		review.toggle(buffer)
		finish(#requests, patch(2))
		assert.matches("[-] M file1.lua", contents(), 1, true)
		assert.matches("[+] M file2.lua", contents(), 1, true)
	end)

	it("bounds expanded pages and evicts the least recently used disk cache", function()
		local paths = {}
		for i = 1, 17 do
			paths[i] = "file" .. i .. ".lua"
		end
		finish(1, files(paths))
		for _, path in ipairs(paths) do
			select_file(path)
			review.toggle(buffer)
			finish(#requests, patch(2))
		end
		local _, expanded = contents():gsub("%[%-%]", "")
		assert.are.equal(8, expanded)
		assert.is_nil(vim.uv.fs_stat(requests[2].job.path))
		select_file(paths[17])
		review.cancel(buffer)
		assert.matches("Requests cancelled", contents(), 1, true)
	end)
end)

describe("bounded JJ patch pages", function()
	it(
		"preserves source line numbers across pages and leaves deleted lines without jump targets",
		function()
			local spool = vim.fn.tempname()
			write_raw(spool, patch(1000))
			local first, next_position =
				page.read(spool, "a.lua", false, { offset = 0, old = 0, new = 0, hunk = false })
			assert.are.equal(395, first.rows[400].new_line)
			local second = assert(page.read(spool, "a.lua", false, next_position))
			assert.are.equal(396, second.rows[1].location.line)
			write_raw(
				spool,
				"diff --git a/a.lua b/a.lua\n--- a/a.lua\n+++ /dev/null\n@@ -1,1 +0,0 @@\n-gone\n"
			)
			local deleted = assert(
				page.read(spool, "a.lua", true, { offset = 0, old = 0, new = 0, hunk = false })
			)
			assert.is_nil(deleted.rows[5].location)
			vim.fn.delete(spool)
		end
	)

	it("refuses an oversized single line rather than silently truncating it", function()
		local spool = vim.fn.tempname()
		write_raw(spool, string.rep("x", 140000))
		local rendered, _, err =
			page.read(spool, "large.txt", false, { offset = 0, old = 0, new = 0, hunk = false })
		vim.fn.delete(spool)
		assert.is_nil(rendered)
		assert.matches("exceeds 128 KiB", err, 1, true)
	end)
end)
