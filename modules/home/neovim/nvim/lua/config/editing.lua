-- Use system clipboard for copy/paste.
vim.opt.clipboard = "unnamedplus"

local code_reference = require("lib.code_reference")

vim.api.nvim_create_user_command("CopyCodeReference", function(opts)
	code_reference.copy(opts.line1, opts.line2)
end, { desc = "Copy current file and line range", range = true })

vim.keymap.set("n", "<leader>cy", function()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	code_reference.copy(line, line)
end, { desc = "Yank code reference" })

vim.keymap.set("x", "<leader>cy", function()
	local anchor_line = vim.fn.getpos("v")[2]
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	code_reference.copy(anchor_line, cursor_line)
end, { desc = "Yank selected code reference" })

-- Tabbing behavior.
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4

-- Split behavior.
vim.opt.splitbelow = true
vim.opt.splitright = true
