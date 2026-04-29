---@type vim.lsp.Config
return {
	cmd = { "rust-analyzer" },
	filetypes = { "rust" },
	root_markers = { "Cargo.toml", "rust-project.json", ".git" },
	settings = {
		["rust-analyzer"] = {
			check = {
				command = "clippy",
				features = "all",
				extraArgs = { "--no-deps" },
			},
			checkOnSave = true,
			assist = {
				importGranularity = "module",
				importPrefix = "self",
			},
			diagnostics = {
				enable = true,
				enableExperimental = true,
			},
			cargo = {
				loadOutDirsFromCheck = true,
				features = "all", -- avoid error: file not included in crate hierarchy
			},
			procMacro = { enable = true },
			inlayHints = {
				chainingHints = true,
				parameterHints = true,
				typeHints = true,
			},
		},
	},
	-- rust-analyzer reads init-only options from initializationOptions, not
	-- workspace settings. Promote settings["rust-analyzer"] so keys like
	-- procMacro and cargo apply at startup.
	-- https://rust-analyzer.github.io/book/configuration.html
	before_init = function(init_params, config)
		if config.settings and config.settings["rust-analyzer"] then
			init_params.initializationOptions = config.settings["rust-analyzer"]
		end
	end,
}
