---@type vim.lsp.Config
return {
	cmd = { "typescript-language-server", "--stdio" },
	filetypes = {
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
	},
	-- Only projects on TypeScript < 7; `tsgo` serves the rest.
	root_dir = require("lib.typescript_server").root_dir("ts_ls"),
	init_options = {
		hostInfo = "neovim",
	},
}
