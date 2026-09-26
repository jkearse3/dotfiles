local jsonl_view = require("lib.jsonl_view")

describe("JSONL view", function()
	local source_buf

	before_each(function()
		source_buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(source_buf, vim.fn.tempname() .. ".jsonl")
		vim.api.nvim_win_set_buf(0, source_buf)
	end)

	after_each(function()
		vim.cmd("silent! only")
		local view_buf = vim.fn.bufnr("jsonl-view://" .. vim.api.nvim_buf_get_name(source_buf))
		if view_buf ~= -1 then
			vim.api.nvim_buf_delete(view_buf, { force = true })
		end
		vim.api.nvim_buf_delete(source_buf, { force = true })
	end)

	it("pretty-prints records in key order separated by blank lines", function()
		local lines = assert(jsonl_view.render({
			'{"z":1,"a":[true]}',
			"",
			'"text"',
		}))

		assert.are.same({
			"{",
			'  "z": 1,',
			'  "a": [',
			"    true",
			"  ]",
			"}",
			"",
			'"text"',
		}, lines)
	end)

	it("reports the line number of invalid JSON", function()
		local lines, err = jsonl_view.render({ '{"a":1}', '{"b":' })

		assert.is_nil(lines)
		assert.matches("line 2: invalid JSON", err, 1, true)
	end)

	it("opens a read-only view in the current window without modifying the source", function()
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":1}' })
		vim.bo[source_buf].modified = false
		local source_win = vim.api.nvim_get_current_win()
		local window_count = #vim.api.nvim_list_wins()

		jsonl_view.open(source_buf)

		local view_buf = vim.api.nvim_get_current_buf()
		assert.are_not.equal(source_buf, view_buf)
		assert.are.equal(source_win, vim.api.nvim_get_current_win())
		assert.are.equal(window_count, #vim.api.nvim_list_wins())
		assert.are.same(
			{ "{", '  "a": 1', "}" },
			vim.api.nvim_buf_get_lines(view_buf, 0, -1, false)
		)
		assert.is_false(vim.bo[view_buf].modifiable)
		assert.are.equal("nofile", vim.bo[view_buf].buftype)
		assert.are.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(source_buf, 0, -1, false))
		assert.is_false(vim.bo[source_buf].modified)
	end)

	it("refreshes an open view in place", function()
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":1}' })
		jsonl_view.open(source_buf)
		local view_buf = vim.api.nvim_get_current_buf()
		local window_count = #vim.api.nvim_list_wins()

		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":2}' })
		jsonl_view.open(source_buf)

		assert.are.equal(view_buf, vim.api.nvim_get_current_buf())
		assert.are.equal(window_count, #vim.api.nvim_list_wins())
		assert.are.same(
			{ "{", '  "a": 2', "}" },
			vim.api.nvim_buf_get_lines(view_buf, 0, -1, false)
		)
	end)

	it("returns to the source buffer on q and keeps the view for later", function()
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":1}' })
		jsonl_view.open(source_buf)
		local view_buf = vim.api.nvim_get_current_buf()
		assert.are.equal("expr", vim.wo.foldmethod)

		vim.api.nvim_feedkeys("q", "x", false)

		assert.are.equal(source_buf, vim.api.nvim_get_current_buf())
		assert.are.equal("manual", vim.wo.foldmethod)
		assert.is_true(vim.api.nvim_buf_is_valid(view_buf))
		assert.is_true(vim.bo[view_buf].buflisted)

		vim.api.nvim_win_set_buf(0, view_buf)

		assert.are.same(
			{ "{", '  "a": 1', "}" },
			vim.api.nvim_buf_get_lines(view_buf, 0, -1, false)
		)
		assert.are.equal("expr", vim.wo.foldmethod)
	end)

	it("refreshes a hidden view instead of creating another", function()
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":1}' })
		jsonl_view.open(source_buf)
		local view_buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_win_set_buf(0, source_buf)

		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":2}' })
		jsonl_view.open(source_buf)

		assert.are.equal(view_buf, vim.api.nvim_get_current_buf())
		assert.are.same(
			{ "{", '  "a": 2', "}" },
			vim.api.nvim_buf_get_lines(view_buf, 0, -1, false)
		)
	end)

	it("returns to a re-edited source buffer on q", function()
		local source_name = vim.api.nvim_buf_get_name(source_buf)
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":1}' })
		jsonl_view.open(source_buf)
		local view_buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_delete(source_buf, { force = true })

		source_buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(source_buf, source_name)
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { '{"a":2}' })
		vim.api.nvim_win_set_buf(0, source_buf)
		jsonl_view.open(source_buf)
		assert.are.equal(view_buf, vim.api.nvim_get_current_buf())

		vim.api.nvim_feedkeys("q", "x", false)

		assert.are.equal(source_buf, vim.api.nvim_get_current_buf())
		assert.is_true(vim.api.nvim_buf_is_valid(view_buf))
	end)
end)
