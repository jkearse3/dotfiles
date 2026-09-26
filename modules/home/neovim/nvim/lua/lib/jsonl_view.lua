local M = {}

-- Raw input keeps line numbers for errors; strings are re-encoded so raw
-- output prints them as JSON, and each record is followed by an empty line.
local RENDER_PROGRAM = [[
select(test("\\S"))
| . as $raw
| (try fromjson catch error("line \(input_line_number): invalid JSON: \($raw)"))
| (if type == "string" then tojson else . end), ""
]]

--- Pretty-prints JSONL records with jq, preserving key order and separating
--- records with a blank line. Blank input lines are skipped.
---@param jsonl_lines string[]
---@return string[]? lines
---@return string? error Includes the 1-based line number of invalid JSON.
function M.render(jsonl_lines)
	if vim.fn.executable("jq") ~= 1 then
		return nil, "JSONL view requires jq on PATH"
	end

	local result = vim.system({ "jq", "--raw-input", "--raw-output", RENDER_PROGRAM }, {
		stdin = table.concat(jsonl_lines, "\n") .. "\n",
		text = true,
	}):wait()
	if result.code ~= 0 then
		return nil, "JSONL view: " .. vim.trim(result.stderr)
	end

	local lines = vim.split(result.stdout, "\n", { plain = true })
	while #lines > 0 and lines[#lines] == "" do
		lines[#lines] = nil
	end
	return lines
end

---@param name string
---@return integer?
local function find_buffer(name)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(buf) == name then
			return buf
		end
	end
end

--- Creates a listed view buffer that persists while hidden; `q` returns its
--- window to the source buffer most recently recorded by `open`.
---@param name string
---@return integer
local function create_view_buffer(name)
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(buf, name)
	vim.bo[buf].filetype = "json"
	vim.keymap.set("n", "q", function()
		local source_buf = vim.b[buf].jsonl_view_source
		if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
			vim.api.nvim_win_set_buf(0, source_buf)
		else
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end, {
		buffer = buf,
		desc = "Return from JSONL view",
	})
	return buf
end

--- Focuses an existing window for the view, or shows it in the current window.
--- Fold options are set local to the view so the window's other buffers keep theirs.
---@param buf integer
local function show_view_buffer(buf)
	local win = vim.fn.bufwinid(buf)
	if win == -1 then
		vim.api.nvim_win_set_buf(0, buf)
	else
		vim.api.nvim_set_current_win(win)
	end

	vim.wo[0][0].foldmethod = "expr"
	vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
	vim.wo[0][0].foldlevel = 99
end

--- Opens a read-only, pretty-printed view of a JSONL buffer without modifying it.
--- Reopening the view for the same source refreshes it in place. Invalid JSON
--- is reported as a notification and leaves any existing view unchanged.
---@param source_buf? integer Defaults to the current buffer.
function M.open(source_buf)
	source_buf = source_buf or vim.api.nvim_get_current_buf()

	local lines, err = M.render(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false))
	if not lines then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	local view_name = "jsonl-view://" .. vim.api.nvim_buf_get_name(source_buf)
	local view_buf = find_buffer(view_name) or create_view_buffer(view_name)
	-- A re-edited source file gets a new buffer number under the same view name.
	vim.b[view_buf].jsonl_view_source = source_buf
	vim.bo[view_buf].modifiable = true
	vim.api.nvim_buf_set_lines(view_buf, 0, -1, false, lines)
	vim.bo[view_buf].modifiable = false

	show_view_buffer(view_buf)
end

return M
