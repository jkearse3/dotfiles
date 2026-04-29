---@type vim.lsp.Config
return {
	cmd = { "yaml-language-server", "--stdio" },
	filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values" },
	root_markers = { ".git" },
	-- yamlls reports documentFormattingProvider as disabled at init, which
	-- prevents conform.nvim from seeing it as a formatter. Patch it manually.
	on_init = function(client)
		client.server_capabilities.documentFormattingProvider = true
	end,
	settings = {
		redhat = {
			telemetry = {
				enabled = false,
			},
		},
		yaml = {
			format = {
				enable = true,
			},
		},
	},
}
