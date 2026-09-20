local M = {}
local process = require("lib.jj_review_process")

---@class lib.jj_review.Position
---@field offset integer Byte offset in the cached patch.
---@field old integer Next old-side line number.
---@field new integer Next new-side line number.
---@field hunk boolean Whether the offset lies inside a text hunk.

--- Renders at most 400 patch lines / 128 KiB, preserving hunk counters across pages.
--- Uses the retained review renderer's row model and syntax fragments, without parsing the
--- entire file or retaining all preceding pages. Oversized individual lines fail explicitly.
---@param spool string
---@param path string Destination path from JJ's changed-file list.
---@param deleted boolean
---@param position lib.jj_review.Position
---@return lib.jj_diff_render.Result? rendered
---@return lib.jj_review.Position? next_position
---@return string? error
function M.read(spool, path, deleted, position)
	local content, err = process.read(spool, 131072, position.offset)
	if not content then
		return nil, nil, err
	end
	local state = vim.deepcopy(position)
	local result = {
		lines = {},
		rows = {},
		quickfix = {},
		syntax_fragments = {},
		file_rows = {},
		hunk_rows = {},
	}
	local old_fragment = { path = path, lines = {}, rows = {} }
	local new_fragment = { path = path, lines = {}, rows = {} }
	local consumed = 0
	for _ = 1, 400 do
		if consumed == #content then
			break
		end
		local boundary = content:find("\n", consumed + 1, true)
		if not boundary then
			local size = assert(vim.uv.fs_stat(spool)).size
			if position.offset + #content < size then
				if consumed == 0 then
					return nil, nil, "Patch line exceeds 128 KiB; inspect this file externally"
				end
				break
			end
			boundary = #content + 1
		end
		local line = content:sub(consumed + 1, boundary - 1)
		consumed = math.min(boundary, #content)
		local row = #result.lines + 1
		local item = { kind = "metadata", text = line, path = path }
		local old, new = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
		if old then
			state.old, state.new, state.hunk = tonumber(old), tonumber(new), true
			item.kind = "hunk"
			item.new_line = state.new
			result.hunk_rows[#result.hunk_rows + 1] = row
		elseif line:match("^diff %-%-git ") then
			state.hunk = false
		elseif state.hunk then
			local prefix = line:sub(1, 1)
			if prefix == " " or prefix == "+" or prefix == "-" then
				item.kind = prefix == " " and "context" or prefix == "+" and "add" or "delete"
				item.text = line:sub(2)
				if prefix ~= "+" then
					item.old_line = state.old
					state.old = state.old + 1
					old_fragment.lines[#old_fragment.lines + 1] = item.text
					if prefix == "-" then
						old_fragment.rows[#old_fragment.lines] = row
					end
				end
				if prefix ~= "-" then
					item.new_line = state.new
					if not deleted then
						item.location = { path = path, line = state.new }
					end
					state.new = state.new + 1
					new_fragment.lines[#new_fragment.lines + 1] = item.text
					new_fragment.rows[#new_fragment.lines] = row
				end
			end
		end
		result.lines[row], result.rows[row] = item.text, item
	end
	result.syntax_fragments = { old_fragment, new_fragment }
	state.offset = position.offset + consumed
	local size = assert(vim.uv.fs_stat(spool)).size
	return result, state.offset < size and state or nil
end

return M
