local typescript_server = require("lib.typescript_server")

-- TypeScript 7's native language server, for projects that ship TypeScript 7 or
-- no TypeScript; `ts_ls` serves projects on TypeScript < 7.
---@type vim.lsp.Config
return {
	-- Starts the project's own TypeScript 7 binary, or the global `tsc`.
	cmd = function(dispatchers, config)
		local selection = typescript_server.select(assert(config.root_dir))
		if selection.server ~= "tsgo" then
			error(
				"tsgo: project at "
					.. config.root_dir
					.. " now uses TypeScript < 7; reopen the buffer to start ts_ls"
			)
		end

		return vim.lsp.rpc.start(selection.cmd, dispatchers, {
			cwd = config.cmd_cwd,
			env = config.cmd_env,
			detached = config.detached,
		})
	end,
	filetypes = {
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
	},
	root_dir = typescript_server.root_dir("tsgo"),
}
