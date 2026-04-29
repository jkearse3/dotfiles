local toggle_quickfix_list = function()
	vim.cmd(vim.fn.getqflist({ winid = 0 }).winid ~= 0 and "cclose" or "copen")
end
vim.keymap.set("n", "<leader>q", toggle_quickfix_list, { desc = "Toggle quickfix list" })
