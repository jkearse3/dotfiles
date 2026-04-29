---@type vim.lsp.Config
return {
	cmd = { "buf", "lsp", "serve", "--log-format=text" },
	filetypes = { "proto" },
	root_markers = { "buf.yaml", ".git" },
	reuse_client = function(client, config)
		if not config.root_dir then
			return false
		end
		-- Reuse existing client if its root contains the new buffer's root,
		-- preventing duplicate server instances across proto subdirectories.
		return client.root_dir ~= nil and config.root_dir:find(client.root_dir, 1, true) == 1
	end,
}
