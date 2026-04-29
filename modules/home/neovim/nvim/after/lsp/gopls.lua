---@type vim.lsp.Config
return {
	cmd = { "gopls" },
	filetypes = { "go", "gomod", "gowork", "gotmpl" },
	root_markers = { "go.work", "go.mod", ".git" },
	settings = {
		gopls = {
			gofumpt = true,
			codelenses = {
				gc_details = false,
				generate = true,
				regenerate_cgo = true,
				run_govulncheck = true,
				test = true,
				tidy = true,
				upgrade_dependency = true,
				vendor = true,
			},
			hints = {
				assignVariableTypes = true,
				compositeLiteralFields = true,
				compositeLiteralTypes = true,
				constantValues = true,
				functionTypeParameters = true,
				parameterNames = true,
				rangeVariableTypes = true,
			},
			analyses = {
				nilness = true,
				unusedparams = true,
				unusedwrite = true,
				useany = true,
			},
			usePlaceholders = false,
			completeUnimported = true,
			staticcheck = true,
			directoryFilters = {
				"-.git",
				"-.vscode",
				"-.idea",
				"-.vscode-test",
				"-node_modules",
			},
			semanticTokens = true,
		},
	},
	on_attach = function(client, bufnr)
		-- Workaround for semanticTokens issues.
		-- As of v0.11.0, gopls does not send a Semantic Token legend (in a
		-- client/registerCapability message) unless the client supports dynamic
		-- registration. Neovim's LSP client does not support dynamic registration
		-- for semantic tokens, so we need to declare those server_capabilities
		-- ourselves for the time being.
		-- See https://github.com/golang/go/issues/54531#issuecomment-1464982242.
		if client.name == "gopls" and not client.server_capabilities.semanticTokensProvider then
			local semantic = client.config.capabilities.textDocument.semanticTokens
			client.server_capabilities.semanticTokensProvider = {
				full = true,
				legend = {
					tokenModifiers = semantic.tokenModifiers,
					tokenTypes = semantic.tokenTypes,
				},
				range = true,
			}
		end

		-- vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
	end,
}
