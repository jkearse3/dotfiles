--- Renders parsed JJ patches as syntax-aware stacked source diffs.
---@class lib.jj_diff_render
local M = {}

---@alias lib.jj_diff_render.LineKind "file"|"metadata"|"hunk"|"context"|"add"|"delete"|"separator"

---@class lib.jj_diff_render.SourceLine
---@field kind "context"|"add"|"delete"
---@field text string
---@field old_line? integer
---@field new_line? integer
---@field location? lib.jj_diff.Location

---@class lib.jj_diff_render.Line
---@field kind lib.jj_diff_render.LineKind
---@field text string
---@field path? string
---@field old_line? integer
---@field new_line? integer
---@field location? lib.jj_diff.Location
---@field changed_start? integer Zero-based byte column where an exact edit begins.
---@field changed_end? integer Zero-based exclusive byte column where an exact edit ends.

---@class lib.jj_diff_render.SyntaxFragment
---@field path string
---@field lines string[]
---@field rows table<integer, integer> Rendered rows keyed by one-based fragment row.

---@class lib.jj_diff_render.Result
---@field lines string[]
---@field rows table<integer, lib.jj_diff_render.Line>
---@field quickfix lib.jj_diff.PatchIndexEntry[]
---@field syntax_fragments lib.jj_diff_render.SyntaxFragment[]

local namespace = vim.api.nvim_create_namespace("jj-diff-render")
local autocmd_group = vim.api.nvim_create_augroup("JjDiffRender", { clear = true })
local rendered_buffers = {}

local function append_line(result, line)
	local row = #result.lines + 1
	table.insert(result.lines, line.text)
	result.rows[row] = line
	return row
end

local function display_text(value)
	return (value or "unknown file"):gsub("[%c]", function(character)
		local names = { ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
		return names[character] or string.format("\\x%02x", character:byte())
	end)
end

local function display_path(file)
	if not file.old_path then
		return string.format("%s  [new file]", display_text(file.new_path))
	end
	if not file.new_path then
		return string.format("%s  [deleted]", display_text(file.old_path))
	end
	if file.old_path ~= file.new_path then
		local arrow = file.copy and "⇢" or "→"
		local suffix = file.copy and "  [copy]" or ""
		return string.format(
			"%s %s %s%s",
			display_text(file.old_path),
			arrow,
			display_text(file.new_path),
			suffix
		)
	end
	return display_text(file.new_path)
end

local function metadata_lines(parsed, file, next_file_row)
	local lines = {}
	local first_hunk_row = file.hunks[1] and file.hunks[1].row or next_file_row
	for row = file.row + 1, first_hunk_row - 1 do
		local line = parsed.lines[row]
		if
			line
			and (
				line:match("^new file mode ")
				or line:match("^deleted file mode ")
				or line:match("^old mode ")
				or line:match("^new mode ")
				or line:match("^similarity index ")
				or line:match("^dissimilarity index ")
				or line:match("^Binary files ")
				or line == "GIT binary patch"
			)
		then
			table.insert(lines, line)
		end
	end
	return lines
end

local function utf8_characters(value)
	local characters = {}
	local byte = 1
	for index = 0, vim.fn.strchars(value) - 1 do
		local character = vim.fn.strcharpart(value, index, 1)
		table.insert(characters, { text = character, byte = byte - 1 })
		byte = byte + #character
	end
	return characters
end

--- Finds the changed byte span after removing a shared UTF-8 prefix and suffix.
---@param before string
---@param after string
---@return integer? before_start
---@return integer? before_end
---@return integer? after_start
---@return integer? after_end
function M.changed_spans(before, after)
	if before == after then
		return nil
	end

	local before_chars = utf8_characters(before)
	local after_chars = utf8_characters(after)
	local prefix = 0
	while
		prefix < #before_chars
		and prefix < #after_chars
		and before_chars[prefix + 1].text == after_chars[prefix + 1].text
	do
		prefix = prefix + 1
	end

	local suffix = 0
	while
		suffix < #before_chars - prefix
		and suffix < #after_chars - prefix
		and before_chars[#before_chars - suffix].text == after_chars[#after_chars - suffix].text
	do
		suffix = suffix + 1
	end

	local before_start = before_chars[prefix + 1] and before_chars[prefix + 1].byte or #before
	local after_start = after_chars[prefix + 1] and after_chars[prefix + 1].byte or #after
	local before_end_index = #before_chars - suffix
	local after_end_index = #after_chars - suffix
	local before_end = before_end_index > 0
			and before_chars[before_end_index].byte + #before_chars[before_end_index].text
		or 0
	local after_end = after_end_index > 0
			and after_chars[after_end_index].byte + #after_chars[after_end_index].text
		or 0
	return before_start, before_end, after_start, after_end
end

local function mark_changed_pairs(rows, deleted_rows, added_rows)
	for index = 1, math.min(#deleted_rows, #added_rows) do
		local deleted = rows[deleted_rows[index]]
		local added = rows[added_rows[index]]
		local deleted_start, deleted_end, added_start, added_end =
			M.changed_spans(deleted.text, added.text)
		deleted.changed_start = deleted_start
		deleted.changed_end = deleted_end
		added.changed_start = added_start
		added.changed_end = added_end
	end
end

local function append_source_block(result, file, hunk, parsed)
	local old_fragment = { path = file.old_path or file.new_path, lines = {}, rows = {} }
	local new_fragment = { path = file.new_path or file.old_path, lines = {}, rows = {} }
	local deleted_rows = {}
	local added_rows = {}
	local function flush_changed_block()
		mark_changed_pairs(result.rows, deleted_rows, added_rows)
		deleted_rows = {}
		added_rows = {}
	end
	local old_line = hunk.old_start
	local new_line = hunk.new_start

	local next_hunk_row
	for index, candidate in ipairs(file.hunks) do
		if candidate == hunk then
			next_hunk_row = file.hunks[index + 1] and file.hunks[index + 1].row
			break
		end
	end
	local file_index
	for index, candidate in ipairs(parsed.files) do
		if candidate == file then
			file_index = index
			break
		end
	end
	local next_file_row = parsed.files[file_index + 1] and parsed.files[file_index + 1].row
	local last_row = (next_hunk_row or next_file_row or (#parsed.lines + 1)) - 1
	local previous_kind

	for patch_row = hunk.row + 1, last_row do
		local patch_line = parsed.lines[patch_row]
		local prefix = patch_line and patch_line:sub(1, 1)
		if patch_line == "\\ No newline at end of file" and previous_kind then
			local side = previous_kind == "delete" and "old" or "new"
			append_line(result, {
				kind = "metadata",
				text = string.format("  ↳ %s side: no newline at end of file", side),
				path = file.new_path or file.old_path,
			})
		elseif prefix == " " or prefix == "+" or prefix == "-" then
			local kind = prefix == " " and "context" or (prefix == "+" and "add" or "delete")
			previous_kind = kind
			local line = {
				kind = kind,
				text = patch_line:sub(2),
				path = file.new_path or file.old_path,
			}
			if kind ~= "add" then
				line.old_line = old_line
				old_line = old_line + 1
			end
			if kind ~= "delete" then
				line.new_line = new_line
				line.location = file.new_path and { path = file.new_path, line = new_line } or nil
				new_line = new_line + 1
			end

			if kind == "context" or (kind == "delete" and #added_rows > 0) then
				flush_changed_block()
			end

			local render_row = append_line(result, line)
			if kind ~= "add" then
				table.insert(old_fragment.lines, line.text)
				if kind == "delete" then
					old_fragment.rows[#old_fragment.lines] = render_row
					table.insert(deleted_rows, render_row)
				end
			end
			if kind ~= "delete" then
				table.insert(new_fragment.lines, line.text)
				new_fragment.rows[#new_fragment.lines] = render_row
				if kind == "add" then
					table.insert(added_rows, render_row)
				end
			end
		end
	end

	flush_changed_block()
	if old_fragment.path and #old_fragment.lines > 0 and not vim.tbl_isempty(old_fragment.rows) then
		table.insert(result.syntax_fragments, old_fragment)
	end
	if new_fragment.path and #new_fragment.lines > 0 and not vim.tbl_isempty(new_fragment.rows) then
		table.insert(result.syntax_fragments, new_fragment)
	end
end

--- Converts a parsed Git patch into source-shaped review lines and navigation metadata.
---@param parsed lib.jj_diff.ParsedPatch
---@return lib.jj_diff_render.Result
function M.render(parsed)
	local result = { lines = {}, rows = {}, quickfix = {}, syntax_fragments = {} }
	for file_index, file in ipairs(parsed.files) do
		if #result.lines > 0 then
			append_line(result, { kind = "separator", text = "" })
		end

		local path = file.new_path or file.old_path
		local file_row = append_line(result, {
			kind = "file",
			text = display_path(file),
			path = path,
		})
		table.insert(result.quickfix, { lnum = file_row, text = display_text(path) })

		local next_file_row = parsed.files[file_index + 1] and parsed.files[file_index + 1].row
		for _, metadata in
			ipairs(metadata_lines(parsed, file, next_file_row or (#parsed.lines + 1)))
		do
			append_line(result, { kind = "metadata", text = "  " .. metadata, path = path })
		end

		for _, hunk in ipairs(file.hunks) do
			local hunk_row = append_line(result, {
				kind = "hunk",
				text = "  " .. parsed.lines[hunk.row],
				path = path,
			})
			table.insert(result.quickfix, {
				lnum = hunk_row,
				text = string.format("%s:%d", display_text(path), hunk.new_start),
			})
			append_source_block(result, file, hunk, parsed)
		end
	end

	if #result.lines == 0 then
		result.lines = { "No changes" }
		result.rows[1] = { kind = "metadata", text = "No changes" }
	end
	return result
end

local function set_default_highlights()
	vim.api.nvim_set_hl(0, "JjDiffFileHeader", { default = true, link = "Title" })
	vim.api.nvim_set_hl(0, "JjDiffHunkHeader", { default = true, link = "DiffText" })
	vim.api.nvim_set_hl(0, "JjDiffMetadata", { default = true, link = "Comment" })
	vim.api.nvim_set_hl(0, "JjDiffAddedText", { default = true, link = "DiffText" })
	vim.api.nvim_set_hl(0, "JjDiffDeletedText", { default = true, link = "DiffText" })
end

local function add_highlight(buffer, row, start_col, end_col, group, priority, whole_line)
	local options = {
		end_col = end_col,
		hl_group = group,
		hl_eol = whole_line or false,
		priority = priority,
	}
	vim.api.nvim_buf_set_extmark(buffer, namespace, row - 1, start_col, options)
end

local function apply_line_highlights(buffer, rendered)
	for row, line in pairs(rendered.rows) do
		if line.kind == "file" then
			add_highlight(buffer, row, 0, #line.text, "JjDiffFileHeader", 30, true)
		elseif line.kind == "hunk" then
			add_highlight(buffer, row, 0, #line.text, "JjDiffHunkHeader", 30, true)
		elseif line.kind == "metadata" then
			add_highlight(buffer, row, 0, #line.text, "JjDiffMetadata", 30, false)
		elseif line.kind == "add" then
			add_highlight(buffer, row, 0, #line.text, "DiffAdd", 10, true)
		elseif line.kind == "delete" then
			add_highlight(buffer, row, 0, #line.text, "DiffDelete", 10, true)
		end

		if line.changed_start and line.changed_end and line.changed_start < line.changed_end then
			local group = line.kind == "add" and "JjDiffAddedText" or "JjDiffDeletedText"
			add_highlight(buffer, row, line.changed_start, line.changed_end, group, 200, false)
		end
	end
end

local function apply_syntax_fragment(buffer, fragment)
	local filetype = vim.filetype.match({ filename = fragment.path })
	local language = filetype and vim.treesitter.language.get_lang(filetype)
	if not language or not pcall(vim.treesitter.language.inspect, language) then
		return
	end

	local source = table.concat(fragment.lines, "\n")
	local ok, parser = pcall(vim.treesitter.get_string_parser, source, language)
	if not ok then
		return
	end
	local trees = parser:parse()
	local query = vim.treesitter.query.get(language, "highlights")
	if not trees[1] or not query then
		return
	end

	for capture, node, metadata in query:iter_captures(trees[1]:root(), source, 0, -1) do
		local capture_metadata = metadata and metadata[capture]
		local range = vim.treesitter.get_range(node, source, capture_metadata)
		local start_row, start_col, end_row, end_col = range[1], range[2], range[4], range[5]
		for source_row = start_row, end_row do
			local render_row = fragment.rows[source_row + 1]
			if render_row then
				local line = fragment.lines[source_row + 1] or ""
				local capture_start = source_row == start_row and start_col or 0
				local capture_end = source_row == end_row and end_col or #line
				if capture_start < capture_end then
					local priority = tonumber(
						metadata
							and (
								metadata.priority
								or capture_metadata and capture_metadata.priority
							)
					) or vim.hl.priorities.treesitter
					add_highlight(
						buffer,
						render_row,
						capture_start,
						capture_end,
						"@" .. query.captures[capture],
						priority,
						false
					)
				end
			end
		end
	end
end

local function configure_window(window)
	vim.wo[window].number = true
	vim.wo[window].relativenumber = false
	vim.wo[window].numberwidth = 12
	vim.wo[window].signcolumn = "no"
	vim.wo[window].statuscolumn = "%!v:lua.require'lib.jj_diff_render'.statuscolumn()"
	vim.wo[window].cursorline = true
end

--- Applies review highlights and gutter behavior to a rendered buffer.
---@param buffer integer
---@param rendered lib.jj_diff_render.Result
function M.decorate(buffer, rendered)
	set_default_highlights()
	vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
	rendered_buffers[buffer] = rendered
	apply_line_highlights(buffer, rendered)
	for _, fragment in ipairs(rendered.syntax_fragments) do
		pcall(apply_syntax_fragment, buffer, fragment)
	end

	vim.api.nvim_clear_autocmds({ group = autocmd_group, buffer = buffer })
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = autocmd_group,
		buffer = buffer,
		callback = function(event)
			local window = vim.api.nvim_get_current_win()
			if vim.api.nvim_win_get_buf(window) == event.buf then
				configure_window(window)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufDelete", {
		group = autocmd_group,
		buffer = buffer,
		once = true,
		callback = function(event)
			rendered_buffers[event.buf] = nil
		end,
	})
	for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
		configure_window(window)
	end
end

--- Formats old/new source line numbers and change markers for the review status column.
---@return string
function M.statuscolumn()
	local window = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local buffer = vim.api.nvim_win_get_buf(window)
	local rendered = rendered_buffers[buffer]
	local line = rendered and rendered.rows[vim.v.lnum]
	if not line then
		return "           "
	end

	local old_number = line.old_line and string.format("%4d", line.old_line) or "    "
	local new_number = line.new_line and string.format("%4d", line.new_line) or "    "
	local marker = line.kind == "add" and "+" or (line.kind == "delete" and "-" or " ")
	local highlight = line.kind == "add" and "DiffAdd"
		or (line.kind == "delete" and "DiffDelete" or "LineNr")
	return string.format("%%#%s#%s %s %s ", highlight, old_number, new_number, marker)
end

return M
