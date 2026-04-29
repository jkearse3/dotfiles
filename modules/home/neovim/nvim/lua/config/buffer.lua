-- Reload buffers when files change externally (formatters, AI assistants, etc.).
vim.opt.autoread = true

-- Delete all listed non-terminal buffers. :%bd sweeps unlisted buffers too (by buffer number range),
-- which kills hidden terminals (fzf-lua, claudecode). This command filters properly.
vim.api.nvim_create_user_command("Bd", function(opts)
	local deleted = 0
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.fn.buflisted(buf) == 1 and vim.bo[buf].buftype ~= "terminal" then
			local ok, err = pcall(function()
				vim.api.nvim_buf_delete(buf, { force = opts.bang })
			end)
			if ok then
				deleted = deleted + 1
			elseif not opts.bang then
				vim.notify(err, vim.log.levels.WARN)
			end
		end
	end
	vim.notify(deleted .. " buffer(s) deleted", vim.log.levels.INFO)
end, { bang = true, desc = "Delete all listed non-terminal buffers" })
