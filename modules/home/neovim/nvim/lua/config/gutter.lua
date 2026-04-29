-- Line numbers.
vim.opt.number = true
vim.opt.relativenumber = true

-- Show absolute line numbers in command-line mode.
vim.api.nvim_create_autocmd("CmdlineEnter", {
	pattern = ":",
	callback = function()
		vim.opt.relativenumber = false
		vim.cmd("redraw")
	end,
})
vim.api.nvim_create_autocmd("CmdlineLeave", {
	pattern = ":",
	callback = function()
		vim.opt.relativenumber = true
	end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
	callback = function()
		local line_count = vim.api.nvim_buf_line_count(0)
		local width = #tostring(line_count)
		vim.opt.numberwidth = width
	end,
})
vim.keymap.set("n", "<leader>n", function()
	vim.wo.relativenumber = not vim.wo.relativenumber
end, { desc = "" })

-- Sign column formatting.
vim.opt.signcolumn = "yes"
vim.opt.statuscolumn = " %l %C %s"
