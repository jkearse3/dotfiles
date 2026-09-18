local jj_diff = require("lib.jj_diff")
local render = require("lib.jj_diff_render")

describe("jj stacked diff rendering", function()
	it("renders source lines with dual line numbers and working-copy locations", function()
		local patch = table.concat({
			"diff --git a/a.lua b/a.lua",
			"index 1111111..2222222 100644",
			"--- a/a.lua",
			"+++ b/a.lua",
			"@@ -1,2 +1,2 @@ function example()",
			"-local before = 1",
			"+local after = 1",
			" return before",
		}, "\n")

		local rendered = render.render(jj_diff.parse_patch(patch))
		assert.are.same({
			"a.lua",
			"  @@ -1,2 +1,2 @@ function example()",
			"local before = 1",
			"local after = 1",
			"return before",
		}, rendered.lines)
		assert.are.same({
			{ lnum = 1, text = "a.lua" },
			{ lnum = 2, text = "a.lua:1" },
		}, rendered.quickfix)
		assert.are.same({
			kind = "delete",
			text = "local before = 1",
			path = "a.lua",
			old_line = 1,
			changed_start = 6,
			changed_end = 12,
		}, rendered.rows[3])
		assert.are.same({
			kind = "add",
			text = "local after = 1",
			path = "a.lua",
			new_line = 1,
			location = { path = "a.lua", line = 1 },
			changed_start = 6,
			changed_end = 11,
		}, rendered.rows[4])
		assert.are.same({
			kind = "context",
			text = "return before",
			path = "a.lua",
			old_line = 2,
			new_line = 2,
			location = { path = "a.lua", line = 2 },
		}, rendered.rows[5])
	end)

	it("separates files and summarizes useful metadata", function()
		local patch = table.concat({
			"diff --git a/old.lua b/new.lua",
			"similarity index 90%",
			"rename from old.lua",
			"rename to new.lua",
			"old mode 100644",
			"new mode 100755",
			"--- a/old.lua",
			"+++ b/new.lua",
			"@@ -1 +1 @@",
			"-old()",
			"+new()",
			"diff --git a/image.png b/image.png",
			"new file mode 100644",
			"index 0000000..1111111",
			"Binary files /dev/null and b/image.png differ",
		}, "\n")

		local rendered = render.render(jj_diff.parse_patch(patch))
		assert.are.same({
			"old.lua → new.lua",
			"  similarity index 90%",
			"  old mode 100644",
			"  new mode 100755",
			"  @@ -1 +1 @@",
			"old()",
			"new()",
			"",
			"image.png  [new file]",
			"  new file mode 100644",
			"  Binary files /dev/null and b/image.png differ",
		}, rendered.lines)
		assert.are.same({
			{ lnum = 1, text = "new.lua" },
			{ lnum = 5, text = "new.lua:1" },
			{ lnum = 9, text = "image.png" },
		}, rendered.quickfix)
		assert.are.same({ 1, 9 }, rendered.file_rows)
		assert.are.same({ 5 }, rendered.hunk_rows)
	end)

	it("escapes control characters in displayed paths", function()
		local patch = table.concat({
			'diff --git "a/weird\\nname.lua" "b/weird\\nname.lua"',
			'--- "a/weird\\nname.lua"',
			'+++ "b/weird\\nname.lua"',
			"@@ -1 +1 @@",
			"-old",
			"+new",
		}, "\n")

		local rendered = render.render(jj_diff.parse_patch(patch))
		assert.are.equal("weird\\nname.lua", rendered.lines[1])
		assert.are.equal("weird\\nname.lua", rendered.quickfix[1].text)
		for _, line in ipairs(rendered.lines) do
			assert.is_nil(line:find("\n", 1, true))
		end
		assert.are.equal("weird\nname.lua", rendered.rows[4].location.path)
	end)

	it("preserves missing final-newline semantics without advancing source lines", function()
		local patch = table.concat({
			"diff --git a/a.txt b/a.txt",
			"--- a/a.txt",
			"+++ b/a.txt",
			"@@ -1 +1 @@",
			"-old",
			"\\ No newline at end of file",
			"+new",
			"\\ No newline at end of file",
		}, "\n")

		local rendered = render.render(jj_diff.parse_patch(patch))
		assert.are.same({
			"a.txt",
			"  @@ -1 +1 @@",
			"old",
			"  ↳ old side: no newline at end of file",
			"new",
			"  ↳ new side: no newline at end of file",
		}, rendered.lines)
		assert.are.equal(1, rendered.rows[3].old_line)
		assert.are.equal(1, rendered.rows[5].new_line)
		assert.are.same({ path = "a.txt", line = 1 }, rendered.rows[5].location)
	end)

	it("pairs exact edits only within contiguous change blocks", function()
		local patch = table.concat({
			"diff --git a/a.txt b/a.txt",
			"--- a/a.txt",
			"+++ b/a.txt",
			"@@ -1,4 +1,4 @@",
			"-alpha old",
			"+alpha new",
			" unchanged",
			"-omega left",
			"+omega right",
		}, "\n")

		local rendered = render.render(jj_diff.parse_patch(patch))
		assert.are.same({ 6, 9 }, {
			rendered.rows[3].changed_start,
			rendered.rows[3].changed_end,
		})
		assert.are.same({ 6, 9 }, {
			rendered.rows[4].changed_start,
			rendered.rows[4].changed_end,
		})
		assert.are.same({ 6, 9 }, {
			rendered.rows[6].changed_start,
			rendered.rows[6].changed_end,
		})
		assert.are.same({ 6, 10 }, {
			rendered.rows[7].changed_start,
			rendered.rows[7].changed_end,
		})
	end)

	it("keeps exact edit spans on UTF-8 byte boundaries", function()
		assert.are.same({ 2, 4, 2, 5 }, { render.changed_spans("a λ z", "a 文 z") })
	end)

	it("centers hunk jumps and places file jumps at the top", function()
		local original = vim.api.nvim_get_current_buf()
		local original_height = vim.api.nvim_win_get_height(0)
		local buffer = vim.api.nvim_create_buf(false, true)
		local lines = {}
		local rows = {}
		for row = 1, 30 do
			lines[row] = "line " .. row
			rows[row] = { kind = "context", text = lines[row], path = "file.lua" }
		end
		local rendered = {
			lines = lines,
			rows = rows,
			quickfix = {},
			syntax_fragments = {},
			file_rows = { 1, 15 },
			hunk_rows = { 3, 10, 17 },
		}
		vim.api.nvim_win_set_height(0, 7)
		render.prepare_window(vim.api.nvim_get_current_win(), buffer)
		vim.api.nvim_set_current_buf(buffer)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
		render.decorate(buffer, rendered)

		vim.api.nvim_win_set_cursor(0, { 3, 0 })
		render.navigate_hunk(1)
		assert.are.same({ 10, 0 }, vim.api.nvim_win_get_cursor(0))
		assert.is_true(math.abs(vim.fn.winline() - 4) <= 1)

		render.navigate_file(1)
		assert.are.same({ 15, 0 }, vim.api.nvim_win_get_cursor(0))
		assert.are.equal(1, vim.fn.winline())

		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_win_set_height(0, original_height)
		vim.api.nvim_buf_delete(buffer, { force = true })
	end)

	it("projects source syntax and diff emphasis onto the review buffer", function()
		local patch = table.concat({
			"diff --git a/a.lua b/a.lua",
			"--- a/a.lua",
			"+++ b/a.lua",
			"@@ -1 +1 @@",
			"-local before = 1",
			"+local after = 1",
		}, "\n")
		local rendered = render.render(jj_diff.parse_patch(patch))
		local original = vim.api.nvim_get_current_buf()
		local window = vim.api.nvim_get_current_win()
		local original_winbar = vim.wo.winbar
		local original_statuscolumn = vim.wo.statuscolumn
		local buffer = vim.api.nvim_create_buf(false, true)
		vim.wo.winbar = "ORIGINAL"
		vim.wo.statuscolumn = "ORIGINAL_STATUS"
		render.prepare_window(window, buffer)
		vim.api.nvim_set_current_buf(buffer)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, rendered.lines)

		render.decorate(buffer, rendered)

		local groups = {}
		for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true })) do
			groups[mark[4].hl_group] = true
		end
		assert.is_true(groups["@keyword"])
		assert.is_true(groups.DiffAdd)
		assert.is_true(groups.DiffDelete)
		assert.is_true(groups.JjDiffAddedText)
		assert.is_true(groups.JjDiffDeletedText)
		assert.are.equal(12, vim.wo.numberwidth)
		assert.truthy(vim.wo.statuscolumn:find("jj_diff_render", 1, true))
		render.set_review_state(buffer, "jj revision test", "stale")
		assert.truthy(render.winbar():find("jj revision test", 1, true))
		assert.truthy(render.winbar():find("file 1/1 · hunk 1/1", 1, true))
		assert.truthy(render.winbar():find("[stale]", 1, true))

		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		render.navigate_hunk(1)
		assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
		render.navigate_hunk(1)
		assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
		render.navigate_file(1)
		assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))

		vim.cmd("vsplit")
		local second_window = vim.api.nvim_get_current_win()
		local temporary = vim.api.nvim_create_buf(false, true)
		vim.wo[second_window].statuscolumn = "CUSTOM"
		vim.api.nvim_win_set_buf(second_window, temporary)
		assert.is_nil(vim.wo[second_window].statuscolumn:find("jj_diff_render", 1, true))
		vim.api.nvim_win_set_buf(second_window, buffer)
		assert.truthy(vim.wo[second_window].statuscolumn:find("jj_diff_render", 1, true))
		vim.api.nvim_win_close(second_window, true)

		vim.api.nvim_set_current_buf(original)
		assert.are.equal("ORIGINAL", vim.wo[window].winbar)
		assert.are.equal("ORIGINAL_STATUS", vim.wo[window].statuscolumn)
		vim.wo[window].winbar = original_winbar
		vim.wo[window].statuscolumn = original_statuscolumn
		vim.api.nvim_buf_delete(temporary, { force = true })
		vim.api.nvim_buf_delete(buffer, { force = true })
	end)
end)
