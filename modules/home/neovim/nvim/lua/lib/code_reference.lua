local M = {}

--- Builds a file-and-line reference suitable for pasting into an agent prompt.
---@param buffer_path string
---@param cwd string
---@param first_line integer
---@param last_line integer
---@return string? reference
---@return string? error
function M.build(buffer_path, cwd, first_line, last_line)
	if buffer_path == "" then
		return nil, "Current buffer does not have a file path"
	end

	local normalized_path = vim.fs.normalize(buffer_path)
	local display_path = vim.fs.relpath(vim.fs.normalize(cwd), normalized_path) or normalized_path
	local range_start = math.min(first_line, last_line)
	local range_end = math.max(first_line, last_line)

	if range_start == range_end then
		return string.format("%s:%d", display_path, range_start)
	end
	return string.format("%s:%d-%d", display_path, range_start, range_end)
end

--- Copies a reference to the current file and supplied line range.
---@param first_line integer
---@param last_line integer
---@return string? reference
function M.copy(first_line, last_line)
	local reference, err =
		M.build(vim.api.nvim_buf_get_name(0), vim.fn.getcwd(), first_line, last_line)
	if not reference then
		vim.notify(err, vim.log.levels.WARN)
		return nil
	end

	vim.fn.setreg("+", reference)
	vim.notify("Copied code reference: " .. reference, vim.log.levels.INFO)
	return reference
end

return M
