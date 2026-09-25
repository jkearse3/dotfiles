describe("statusline", function()
	local statusline = require("lib.statusline")
	local previous_columns, previous_laststatus, window, buffer

	before_each(function()
		previous_columns, previous_laststatus = vim.o.columns, vim.o.laststatus
		vim.o.laststatus = 3
		window = vim.api.nvim_get_current_win()
		buffer = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_win_set_buf(window, buffer)
		vim.g.actual_curwin = window
	end)

	after_each(function()
		vim.o.columns, vim.o.laststatus = previous_columns, previous_laststatus
		vim.g.actual_curwin = nil
		vim.api.nvim_buf_delete(buffer, { force = true })
	end)

	it("shows the mode name, relative file name, and filetype in narrow windows", function()
		vim.o.columns = 100
		vim.bo[buffer].filetype = "lua"

		assert.are.equal(
			"%#StatusLineModeNormal# NORMAL %#StatusLineFilename# %f%m%r %<%=%#StatusLineFileinfo# lua ",
			statusline.render()
		)
	end)

	it("shows the full path and file details in wide windows", function()
		vim.o.columns = 160
		vim.bo[buffer].filetype = "lua"
		vim.bo[buffer].fileformat = "unix"
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "abc" })

		local line = statusline.render()

		assert.truthy(line:find("%#StatusLineFilename# %F%m%r ", 1, true))
		assert.truthy(
			line:find("%#StatusLineFileinfo# lua " .. vim.o.encoding .. "[unix] 4B ", 1, true)
		)
	end)

	it("omits the filetype when a normal buffer has none", function()
		vim.o.columns = 160
		vim.bo[buffer].fileformat = "unix"

		assert.truthy(
			statusline
				.render()
				:find("%#StatusLineFileinfo# " .. vim.o.encoding .. "[unix] 0B ", 1, true)
		)
	end)

	it("omits the file info section when a narrow window has no filetype", function()
		vim.o.columns = 100

		assert.are.equal(
			"%#StatusLineModeNormal# NORMAL %#StatusLineFilename# %f%m%r %<%=",
			statusline.render()
		)
	end)

	it("shows only the full path for inactive windows", function()
		vim.o.laststatus = 2
		vim.g.actual_curwin = -1

		assert.are.equal("%#StatusLineNC#%F%=", statusline.render())
	end)

	it("derives highlights from the colorscheme and bolds mode groups", function()
		vim.api.nvim_set_hl(0, "Normal", { fg = 0xffffff, bg = 0x101010 })
		vim.api.nvim_set_hl(0, "Function", { fg = 0x0000ff })

		statusline.set_highlights()

		local mode_normal = vim.api.nvim_get_hl(0, { name = "StatusLineModeNormal" })
		assert.are.equal(0x101010, mode_normal.fg)
		assert.are.equal(0x0000ff, mode_normal.bg)
		assert.is_true(mode_normal.bold)
	end)
end)
