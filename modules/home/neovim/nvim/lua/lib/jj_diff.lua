--- Provides Git-patch parsing and JJ comparison/attribution queries for the shared review.
--- Query callers must supply a read-only runner; this module owns no jobs, buffers, or UI.
---@class lib.jj_diff
local M = {}
local jj_id = require("lib.jj_id")

---@alias lib.jj_diff.Runner fun(args: string[], cwd?: string): string?, string?

---@class lib.jj_diff.Comparison
---@field repo string Repository root.
---@field target string Commit ID or revset at the new side of the comparison.
---@field from? string Commit ID or revset at the old side of an explicit range.

---@class lib.jj_diff.ReviewSource
---@field kind "revision"|"bookmark"
---@field name string Change ID or bookmark name used to resolve the latest comparison.

---@class lib.jj_diff.ReviewComparison: lib.jj_diff.Comparison
---@field title string Display title used by patch views.
---@field description? string Revision description displayed above preview stats.
---@field source? lib.jj_diff.ReviewSource Identity used to refresh rewritten revisions or bookmarks.

---@class lib.jj_diff.Revision
---@field commit_id string
---@field change_id string
---@field description? string
---@field bookmarks? string[]

---@class lib.jj_diff.Attribution
---@field commit_id string
---@field change_id string
---@field line_number integer
---@field original_line_number integer

---@class lib.jj_diff.Bookmark
---@field name string
---@field target any[] Targets reported by JJ; normal bookmarks have exactly one commit ID.
---@field remote? boolean
---@field display? string Picker label added by `list_bookmarks`.

---@class lib.jj_diff.Location
---@field path string Root-relative working-copy path.
---@field line integer One-based line number.

---@class lib.jj_diff.Hunk
---@field row integer One-based patch-buffer row containing the hunk header.
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field line_map table<integer, integer> Surviving old lines keyed by one-based line number.

---@class lib.jj_diff.ParsedFile
---@field row integer One-based patch-buffer row containing the file header.
---@field old_path? string
---@field new_path? string
---@field copy? boolean Whether the patch describes a copy rather than a rename.
---@field hunks lib.jj_diff.Hunk[]

---@class lib.jj_diff.PatchIndexEntry
---@field lnum integer One-based patch-buffer row.
---@field text string Path or path-and-line label.

---@class lib.jj_diff.ParsedPatch
---@field files lib.jj_diff.ParsedFile[]
---@field rows table<integer, lib.jj_diff.Location> Navigable locations keyed by patch-buffer row.
---@field lines string[] Patch-buffer contents.
---@field quickfix lib.jj_diff.PatchIndexEntry[] File and hunk entries for the patch quickfix list.

--- Decodes newline-delimited JSON, ignoring empty lines.
---@param output string
---@return any[]? values
---@return string? error
local function json_lines(output)
	local values = {}
	for line in output:gmatch("[^\r\n]+") do
		local ok, value = pcall(vim.json.decode, line)
		if not ok then
			return nil, "jj returned invalid JSON: " .. value
		end
		if type(value) ~= "table" then
			return nil, "jj returned invalid JSON record"
		end
		table.insert(values, value)
	end
	return values
end

--- Returns the first line of a possibly empty value.
---@param value? string
---@return string
local function first_line(value)
	return (value or ""):match("^[^\r\n]*") or ""
end

--- Reduces a value to one display-safe line.
---@param value? string
---@return string
local function display_text(value)
	return (first_line(value):gsub("[%c]", " "))
end

--- Checks whether a value has JJ's hexadecimal commit-ID shape.
---@param value any
---@return boolean
local function valid_commit_id(value)
	return type(value) == "string" and value:match("^[0-9a-f]+$") ~= nil
end

--- Builds JJ diff arguments for a revision or explicit range comparison.
---@param comparison lib.jj_diff.Comparison
---@return string[]
local function comparison_args(comparison)
	local args = { "diff" }
	if comparison.from then
		vim.list_extend(args, { "--from", comparison.from, "--to", comparison.target })
	else
		vim.list_extend(args, { "-r", comparison.target })
	end
	return args
end

--- Quotes a root-relative path as an exact JJ `root-file` fileset.
---@param path string
---@return string
local function fileset_path(path)
	local escaped = path:gsub('[\\"%c]', function(char)
		if char == "\\" or char == '"' then
			return "\\" .. char
		end
		return string.format("\\x%02x", char:byte())
	end)
	return 'root-file:"' .. escaped .. '"'
end

--- Builds arguments for a stable, uncolored Git-format patch.
---@param comparison lib.jj_diff.Comparison
---@param path? string Optional root-relative path scope.
---@return string[]
local function comparison_patch_args(comparison, path)
	local args = { "--config", "diff.git.show-path-prefix=true" }
	vim.list_extend(args, comparison_args(comparison))
	vim.list_extend(args, { "--git", "--color", "never" })
	if path then
		vim.list_extend(args, { "--", fileset_path(path) })
	end
	return args
end

--- Builds a structured annotation template that emits only the requested line.
---@param line integer
---@return string
local function annotation_line_template(line)
	return table.concat({
		"if(line_number == ",
		tostring(line),
		', "{\\"commit_id\\":" ++ json(commit.commit_id())',
		' ++ ",\\"change_id\\":" ++ json(commit.change_id())',
		' ++ ",\\"line_number\\":" ++ json(line_number)',
		' ++ ",\\"original_line_number\\":" ++ json(original_line_number) ++ "}\\n")',
	})
end

--- Attributes one working-copy line to the revision that introduced it.
---@param repo string Repository root.
---@param path string Root-relative working-copy path.
---@param line integer One-based working-copy line number.
---@param runner lib.jj_diff.Runner Read-only query runner.
---@return lib.jj_diff.Attribution? attribution
---@return string? error
function M.annotate_line(repo, path, line, runner)
	if type(line) ~= "number" or line < 1 or line % 1 ~= 0 then
		return nil, "JJ line attribution requires a positive line number"
	end
	local output, err = runner({
		"file",
		"annotate",
		"-r",
		"@",
		"-T",
		annotation_line_template(line),
		"--color",
		"never",
		"--",
		path,
	}, repo)
	if not output then
		return nil, err
	end

	local values
	values, err = json_lines(output)
	if not values then
		return nil, err
	end
	if #values == 0 then
		return nil, "JJ returned no attribution for line " .. line
	end
	if #values ~= 1 then
		return nil, "JJ returned ambiguous attribution for line " .. line
	end
	local attribution = values[1]
	if
		not valid_commit_id(attribution.commit_id)
		or type(attribution.change_id) ~= "string"
		or attribution.change_id == ""
		or attribution.line_number ~= line
		or type(attribution.original_line_number) ~= "number"
		or attribution.original_line_number < 1
		or attribution.original_line_number % 1 ~= 0
	then
		return nil, "JJ returned invalid line-attribution data"
	end
	return attribution
end

--- Lists local bookmarks with at least one target and adds picker labels.
---@param repo string Repository root.
---@param runner lib.jj_diff.Runner Read-only query runner.
---@return lib.jj_diff.Bookmark[]? bookmarks
---@return string? error
function M.list_bookmarks(repo, runner)
	local output, err = runner({
		"bookmark",
		"list",
		"--sort",
		"name",
		"-T",
		'json(self) ++ "\\n"',
		"--color",
		"never",
	}, repo)
	if not output then
		return nil, err
	end

	local refs
	refs, err = json_lines(output)
	if not refs then
		return nil, err
	end
	local bookmarks = {}
	for _, bookmark in ipairs(refs) do
		if type(bookmark.name) ~= "string" or bookmark.name == "" then
			return nil, "JJ returned invalid bookmark data"
		end
		if bookmark.target == nil or bookmark.target == vim.NIL then
			bookmark.target = {}
		end
		if type(bookmark.target) ~= "table" then
			return nil, "JJ returned invalid bookmark targets"
		end
		local target = bookmark.target and bookmark.target[1]
		if not bookmark.remote and target ~= nil and target ~= vim.NIL then
			bookmark.display = display_text(bookmark.name)
			table.insert(bookmarks, bookmark)
		end
	end
	return bookmarks
end

--- Finds sorted normal bookmark names that point to a commit.
---@param bookmarks lib.jj_diff.Bookmark[]
---@param commit_id string
---@return string[]
local function normal_bookmarks_at(bookmarks, commit_id)
	local names = {}
	for _, bookmark in ipairs(bookmarks) do
		if #bookmark.target == 1 and bookmark.target[1] == commit_id then
			table.insert(names, bookmark.name)
		end
	end
	table.sort(names)
	return names
end

--- Describes a selected revision's commit-relative diff.
---@param repo string Repository root.
---@param revision lib.jj_diff.Revision
---@return lib.jj_diff.ReviewComparison
function M.revision_comparison(repo, revision)
	return {
		repo = repo,
		target = revision.commit_id,
		title = "jj revision " .. jj_id.short(revision.change_id),
		description = revision.description,
		source = { kind = "revision", name = revision.change_id },
	}
end

--- Describes the range from a bookmark's nearest first-parent bookmark to its target.
---
--- Fails when either endpoint cannot be resolved to one unambiguous commit.
---@param repo string Repository root.
---@param bookmark lib.jj_diff.Bookmark Selected bookmark.
---@param bookmarks lib.jj_diff.Bookmark[] Local bookmarks available as possible bases.
---@param runner lib.jj_diff.Runner Read-only query runner.
---@return lib.jj_diff.ReviewComparison? comparison
---@return string? error
function M.bookmark_comparison(repo, bookmark, bookmarks, runner)
	if #bookmark.target ~= 1 or not valid_commit_id(bookmark.target[1]) then
		return nil, "bookmark " .. bookmark.name .. " has an ambiguous target"
	end
	local target = bookmark.target[1]
	local revset = string.format(
		"heads(first_ancestors(commit_id(%s)) & bookmarks() ~ commit_id(%s))",
		target,
		target
	)
	local output, err = runner({
		"log",
		"--no-graph",
		"-r",
		revset,
		"-T",
		'json(self) ++ "\\n"',
		"--color",
		"never",
	}, repo)
	if not output then
		return nil, err
	end

	local ancestors
	ancestors, err = json_lines(output)
	if not ancestors then
		return nil, err
	end
	if #ancestors == 0 then
		return nil, "bookmark " .. bookmark.name .. " has no first-parent ancestor bookmark"
	end
	if #ancestors ~= 1 or not valid_commit_id(ancestors[1].commit_id) then
		return nil, "bookmark " .. bookmark.name .. " has ambiguous first-parent ancestry"
	end

	local base = ancestors[1].commit_id
	local base_names = normal_bookmarks_at(bookmarks, base)
	if #base_names == 0 then
		return nil, "bookmark " .. bookmark.name .. " has an ambiguous parent bookmark"
	end
	return {
		repo = repo,
		from = base,
		target = target,
		title = string.format("jj bookmark %s..%s", table.concat(base_names, ","), bookmark.name),
		source = { kind = "bookmark", name = bookmark.name },
	}
end

--- Renders a comparison as an uncolored Git patch.
---@param comparison lib.jj_diff.Comparison
---@param path? string Optional root-relative path scope.
---@param runner lib.jj_diff.Runner Read-only query runner.
---@return string? patch
---@return string? error
function M.patch(comparison, path, runner)
	return runner(comparison_patch_args(comparison, path), comparison.repo)
end

local escape_chars = {
	a = "\a",
	b = "\b",
	f = "\f",
	n = "\n",
	r = "\r",
	t = "\t",
	v = "\v",
}

--- Decodes one C-quoted path beginning at a double quote.
---@param value string
---@param start integer One-based index of the opening quote.
---@return string? path
---@return integer? next_index Index immediately after the closing quote.
local function parse_quoted_git_path(value, start)
	local result = {}
	local index = start + 1
	while index <= #value do
		local char = value:sub(index, index)
		if char == '"' then
			return table.concat(result), index + 1
		end
		if char ~= "\\" then
			table.insert(result, char)
			index = index + 1
		else
			index = index + 1
			local escaped = value:sub(index, index)
			if escaped == "" then
				return nil
			end
			if escaped:match("[0-7]") then
				local octal = value:sub(index):match("^[0-7][0-7]?[0-7]?")
				table.insert(result, string.char(tonumber(octal, 8)))
				index = index + #octal
			else
				table.insert(result, escape_chars[escaped] or escaped)
				index = index + 1
			end
		end
	end
	return nil
end

--- Decodes a complete C-quoted Git path, leaving unquoted paths unchanged.
---@param value string
---@return string? path
local function unquote_git_path(value)
	if value:sub(1, 1) ~= '"' then
		return value
	end
	local path, next_index = parse_quoted_git_path(value, 1)
	if next_index ~= #value + 1 then
		return nil
	end
	return path
end

--- Extracts root-relative old and new paths from a Git diff header.
---@param line string
---@return string? old_path
---@return string? new_path
local function diff_header_paths(line)
	local value = line:match("^diff %-%-git (.+)$")
	if not value then
		return nil
	end

	local old_path
	local new_path
	if value:sub(1, 1) == '"' then
		local next_index
		old_path, next_index = parse_quoted_git_path(value, 1)
		if not old_path or value:sub(next_index, next_index) ~= " " then
			return nil
		end
		new_path, next_index = parse_quoted_git_path(value, next_index + 1)
		if not new_path or next_index ~= #value + 1 then
			return nil
		end
	else
		local separator = 1
		repeat
			separator = value:find(" b/", separator, true)
			if not separator then
				return nil
			end
			old_path = value:sub(1, separator - 1)
			new_path = value:sub(separator + 1)
			separator = separator + 1
		until old_path:sub(3) == new_path:sub(3) or not value:find(" b/", separator, true)
	end
	if not old_path:match("^a/") or not new_path:match("^b/") then
		return nil
	end
	return old_path:sub(3), new_path:sub(3)
end

--- Parses an old/new file marker and reports whether the marker matched.
---@param line string
---@param marker string
---@return string? path `nil` for `/dev/null` or malformed paths.
---@return boolean matched
local function marker_path(line, marker)
	if line:sub(1, #marker) ~= marker then
		return nil, false
	end
	local value = line:sub(#marker + 1)
	if value == "/dev/null" then
		return nil, true
	end
	local path = unquote_git_path(value)
	if not path or not path:match("^[ab]/") then
		return nil, true
	end
	return path:sub(3), true
end

--- Extracts the literal path following a rename or copy metadata marker.
---@param line string
---@param marker string
---@return string? path
---@return boolean matched
local function metadata_path(line, marker)
	if line:sub(1, #marker) ~= marker then
		return nil, false
	end
	return line:sub(#marker + 1), true
end

--- Normalizes patch newlines and removes one terminal empty buffer line.
---@param patch string
---@return string[]
local function patch_lines(patch)
	local lines = vim.split(patch:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })
	if lines[#lines] == "" and #lines > 1 then
		table.remove(lines)
	end
	return lines
end

--- Parses a Git patch into files, hunks, navigable rows, and quickfix entries.
---
--- Rows and source locations are one-based to match Neovim buffer and quickfix APIs. Deleted
--- files and deleted lines intentionally have no navigable location.
---@param patch string
---@return lib.jj_diff.ParsedPatch
function M.parse_patch(patch)
	local parsed = { files = {}, rows = {}, lines = patch_lines(patch), quickfix = {} }
	local file
	local hunk
	local old_line
	local new_line

	for row, line in ipairs(parsed.lines) do
		if line:match("^diff %-%-git ") then
			local old_path, new_path = diff_header_paths(line)
			file = { row = row, old_path = old_path, new_path = new_path, hunks = {} }
			table.insert(parsed.files, file)
			hunk = nil
		elseif file then
			local old_start, old_count, new_start, new_count =
				line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
			if old_start then
				old_count = old_count == "" and 1 or tonumber(old_count)
				new_count = new_count == "" and 1 or tonumber(new_count)
				hunk = {
					row = row,
					old_start = tonumber(old_start),
					old_count = old_count,
					new_start = tonumber(new_start),
					new_count = new_count,
					line_map = {},
				}
				table.insert(file.hunks, hunk)
				old_line = hunk.old_start
				new_line = hunk.new_start
			elseif not hunk then
				local old_path, old_marker = marker_path(line, "--- ")
				local rename_from, from_marker = metadata_path(line, "rename from ")
				local copy_from, copy_from_marker = metadata_path(line, "copy from ")
				local new_path, new_marker = marker_path(line, "+++ ")
				local rename_to, to_marker = metadata_path(line, "rename to ")
				local copy_to, copy_to_marker = metadata_path(line, "copy to ")
				if old_marker or from_marker or copy_from_marker then
					file.old_path = old_path or rename_from or copy_from
					file.copy = copy_from_marker or file.copy
				elseif new_marker or to_marker or copy_to_marker then
					file.new_path = new_path or rename_to or copy_to
					file.copy = copy_to_marker or file.copy
				elseif line:match("^new file mode ") then
					file.old_path = nil
				elseif line:match("^deleted file mode ") then
					file.new_path = nil
				end
			elseif line:sub(1, 1) == " " then
				hunk.line_map[old_line] = new_line
				parsed.rows[row] = { path = file.new_path, line = new_line }
				old_line = old_line + 1
				new_line = new_line + 1
			elseif line:sub(1, 1) == "+" then
				parsed.rows[row] = { path = file.new_path, line = new_line }
				new_line = new_line + 1
			elseif line:sub(1, 1) == "-" then
				old_line = old_line + 1
			end
		end
	end

	for _, parsed_file in ipairs(parsed.files) do
		if parsed_file.new_path then
			table.insert(parsed.quickfix, {
				lnum = parsed_file.row,
				text = parsed_file.new_path,
			})
			for _, parsed_hunk in ipairs(parsed_file.hunks) do
				table.insert(parsed.quickfix, {
					lnum = parsed_hunk.row,
					text = string.format("%s:%d", parsed_file.new_path, parsed_hunk.new_start),
				})
			end
		end
	end
	return parsed
end

local function map_parsed_line(parsed, path, line)
	local file
	for _, candidate in ipairs(parsed.files) do
		if candidate.old_path == path and not candidate.copy then
			file = candidate
			break
		end
	end
	if not file then
		return path, line
	end
	if not file.new_path then
		return nil
	end

	local offset = 0
	for _, hunk in ipairs(file.hunks) do
		if hunk.old_count == 0 then
			if line <= hunk.old_start then
				return file.new_path, line + offset
			end
		elseif line < hunk.old_start then
			return file.new_path, line + offset
		elseif line < hunk.old_start + hunk.old_count then
			local mapped = hunk.line_map[line]
			if mapped then
				return file.new_path, mapped
			end
			return nil
		end
		offset = offset + hunk.new_count - hunk.old_count
	end
	return file.new_path, line + offset
end

--- Maps an old-side source location through a patch to the new-side file.
--- Unmentioned files retain their location; renames and insertion offsets are followed.
--- Deleted/replaced lines return nil. Copies never redirect the source location.
---@param patch string
---@param path string Root-relative old-side path.
---@param line integer One-based old-side line number.
---@return string? path
---@return integer? line
function M.map_line(patch, path, line)
	return map_parsed_line(M.parse_patch(patch), path, line)
end

--- Resolves a working-copy line to its location in the responsible revision.
--- JJ annotation stops at renames: both analysis patches use its current literal path.
--- Unrelated files must not consume the attribution budget; unmappable origins are refused.
---@param repo string Repository root.
---@param path string Root-relative working-copy path.
---@param line integer One-based working-copy line number.
---@param runner lib.jj_diff.Runner Read-only query runner.
---@return lib.jj_diff.ReviewComparison? comparison
---@return lib.jj_diff.Location|string? location_or_error
function M.resolve_line_revision(repo, path, line, runner)
	local attribution, err = M.annotate_line(repo, path, line, runner)
	if not attribution then
		return nil, err
	end
	local comparison = M.revision_comparison(repo, attribution)
	local revision_patch
	revision_patch, err = M.patch(comparison, path, runner)
	if not revision_patch then
		return nil, err
	end
	local forward_patch
	forward_patch, err =
		M.patch({ repo = repo, from = attribution.commit_id, target = "@" }, path, runner)
	if not forward_patch then
		return nil, err
	end

	local forward = M.parse_patch(forward_patch)
	local matches = {}
	local seen = {}
	local parsed = M.parse_patch(revision_patch)
	local candidates = vim.tbl_values(parsed.rows)
	for _, file in ipairs(parsed.files) do
		if file.old_path and file.new_path and file.old_path ~= file.new_path and not file.copy then
			table.insert(
				candidates,
				{ path = file.new_path, line = attribution.original_line_number }
			)
		end
	end
	for _, candidate in ipairs(candidates) do
		if candidate.path and candidate.line == attribution.original_line_number then
			local key = candidate.path .. "\0" .. candidate.line
			if not seen[key] then
				seen[key] = true
				local mapped_path, mapped_line =
					map_parsed_line(forward, candidate.path, candidate.line)
				if mapped_path == path and mapped_line == line then
					table.insert(matches, candidate)
				end
			end
		end
	end
	if #matches == 0 then
		return nil, "Attributed line is deleted, copied, or cannot be mapped to this file"
	end
	if #matches ~= 1 then
		return nil, "Attributed line maps ambiguously to this file"
	end
	return comparison, matches[1]
end

return M
