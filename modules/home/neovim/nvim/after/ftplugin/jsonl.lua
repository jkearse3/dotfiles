vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.expandtab = true

vim.api.nvim_buf_create_user_command(0, "JsonlView", function()
	require("lib.jsonl_view").open()
end, { desc = "Open a pretty-printed, read-only view of this JSONL buffer" })
