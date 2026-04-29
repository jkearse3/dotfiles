local M = {}

---@class lib.config.Spec
---@field plugins? (string|vim.pack.Spec)[] Plugin specifications passed to vim.pack.add().
---@field opts? vim.pack.keyset.add Options passed to vim.pack.add().
---@field enabled? boolean Whether to run this config block (default: true).
---@field setup? fun() Callback invoked after plugins are loaded (or immediately if no plugins).

--- Run a config block: optionally load plugins, then call setup.
--- When `spec.enabled` is false, nothing executes.
--- If `vim.pack.add()` errors, `setup` does not run.
--- Errors in `setup` are reported via `vim.notify` without crashing.
---@param spec lib.config.Spec
function M.run(spec)
	if spec.enabled == false then
		return
	end

	if spec.plugins then
		local ok, err = pcall(vim.pack.add, spec.plugins, spec.opts)
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
