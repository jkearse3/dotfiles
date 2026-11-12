local M = {}

---@class lib.config.Spec
---@field plugins? string[] Names of optional packages under a `pack/*/opt` directory on 'packpath' to load with `:packadd`, such as "fzf-lua".
---@field enabled? boolean Whether to run this config block (default: true).
---@field setup? fun() Callback invoked after plugins are loaded (or immediately if no plugins).

--- Run a config block: optionally load plugins, then call setup.
--- When `spec.enabled` is false, nothing executes.
--- Plugins load with `:packadd!` during startup, so Neovim sources their `plugin/`
--- scripts once when init finishes, and with `:packadd` afterwards.
--- If loading a plugin errors, the error is reported via `vim.notify` and `setup` does not run.
--- Errors in `setup` are reported via `vim.notify` without crashing.
---@param spec lib.config.Spec
function M.run(spec)
	if spec.enabled == false then
		return
	end

	if spec.plugins then
		local ok, err = pcall(function()
			for _, name in ipairs(spec.plugins) do
				vim.cmd.packadd({ name, bang = vim.v.vim_did_init == 0 })
			end
		end)
		if not ok then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
	end

	if spec.setup then
		local ok, err = pcall(spec.setup)
		if not ok then
			vim.notify(tostring(err), vim.log.levels.ERROR)
		end
	end
end

return M
