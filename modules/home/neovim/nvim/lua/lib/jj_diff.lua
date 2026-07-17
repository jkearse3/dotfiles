--- Provides JJ diff selection, Git-patch parsing, and working-copy navigation.
---
--- Comparisons identify either one revision or an explicit commit range. Patch views share one
--- retained buffer whose quickfix list indexes files and hunks.
---@class lib.jj_diff
local M = {}

---@alias lib.jj_diff.Runner fun(args: string[], cwd?: string): string?, string?

---@class lib.jj_diff.CommandResult
---@field code integer
---@field stdout? string
---@field stderr? string

---@class lib.jj_diff.Comparison
---@field repo string Repository root.
---@field target string Commit ID or revset at the new side of the comparison.
---@field from? string Commit ID or revset at the old side of an explicit range.

---@class lib.jj_diff.ReviewComparison: lib.jj_diff.Comparison
---@field title string Display title used by patch views.
---@field description? string Revision description displayed above preview stats.

---@class lib.jj_diff.Revision
---@field commit_id string
---@field change_id string
---@field description? string
---@field bookmarks? string[]
---@field display? string Picker label added by `list_revisions`.

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

---@class lib.jj_diff.ChangedFile
---@field path string Root-relative path accepted by JJ filesets.
---@field display string Human-readable path, including rename information.
---@field status string JJ status character.
---@field label string Picker label added by `changed_files`.

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

---@class lib.jj_diff.PickerEntry
---@field display string
---@field path? string

---@alias lib.jj_diff.Preview fun(item: any): string?, string?, string?, string?
---@alias lib.jj_diff.Resolve fun(item: any): lib.jj_diff.ReviewComparison?, string?

local patch_buffer_name = "jj-diff://review"

--- Removes trailing whitespace, treating `nil` as an empty string.
---@param value? string
---@return string
local function trim(value)
	return ((value or ""):gsub("%s+$", ""))
end

--- Extracts a useful error message from a failed JJ process result.
---@param result lib.jj_diff.CommandResult
---@return string
local function command_error(result)
	local message = trim(result.stderr)
	if message == "" then
		message = "jj exited with status " .. result.code
	end
	return message
end

--- Runs JJ synchronously without a pager.
---@param args string[] JJ arguments excluding the executable and pager option.
---@param cwd? string Working directory for the process.
---@return string? output
---@return string? error
local function run_jj(args, cwd)
	local command = { "jj", "--no-pager" }
	vim.list_extend(command, args)
	local result = vim.system(command, { cwd = cwd, text = true }):wait()
	if result.code ~= 0 then
		return nil, command_error(result)
	end
	return result.stdout or ""
end

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

--- Builds arguments for a comparison's uncolored diff stat.
---@param comparison lib.jj_diff.Comparison
---@return string[]
local function comparison_stat_args(comparison)
	local args = comparison_args(comparison)
	vim.list_extend(args, { "--stat", "--color", "never" })
	return args
end

local changed_files_template = table.concat({
	'"{\\"path\\":" ++ stringify(path).escape_json()',
	' ++ ",\\"display\\":" ++ display_diff_path.escape_json()',
	' ++ ",\\"status\\":" ++ status_char.escape_json() ++ "}\\n"',
})

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

--- Builds arguments that render changed files as newline-delimited JSON.
---@param comparison lib.jj_diff.Comparison
---@return string[]
local function comparison_files_args(comparison)
	local args = comparison_args(comparison)
	vim.list_extend(args, { "-T", changed_files_template, "--color", "never" })
	return args
end

--- Resolves the JJ repository containing a working directory.
---@param cwd? string
---@param runner? lib.jj_diff.Runner
---@return string? root
---@return string? error
function M.repo_root(cwd, runner)
	local output, err = (runner or run_jj)({ "root" }, cwd)
	if not output then
		return nil, err
	end
	local root = trim(output)
	if root == "" then
		return nil, "jj returned an empty repository root"
	end
	return root
end

--- Attributes one working-copy line to the revision that introduced it.
---@param repo string Repository root.
---@param path string Root-relative working-copy path.
---@param line integer One-based working-copy line number.
---@param runner? lib.jj_diff.Runner
---@return lib.jj_diff.Attribution? attribution
---@return string? error
function M.annotate_line(repo, path, line, runner)
	if type(line) ~= "number" or line < 1 or line % 1 ~= 0 then
		return nil, "JJ line attribution requires a positive line number"
	end
	local output, err = (runner or run_jj)({
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

--- Lists all revisions with stable identifiers and picker labels.
---@param repo string Repository root.
---@param runner? lib.jj_diff.Runner
---@return lib.jj_diff.Revision[]? revisions
---@return string? error
function M.list_revisions(repo, runner)
	local template = '"{"'
		.. ' ++ "\\"commit_id\\":" ++ json(commit_id)'
		.. ' ++ ",\\"change_id\\":" ++ json(change_id)'
		.. ' ++ ",\\"description\\":" ++ json(description)'
		.. ' ++ ",\\"bookmarks\\":" ++ json(local_bookmarks.map(|b| b.name()))'
		.. ' ++ "}\\n"'
	local output, err = (runner or run_jj)({
		"log",
		"--no-graph",
		"-r",
		"all()",
		"-T",
		template,
		"--color",
		"never",
	}, repo)
	if not output then
		return nil, err
	end

	local revisions
	revisions, err = json_lines(output)
	if not revisions then
		return nil, err
	end
	for _, revision in ipairs(revisions) do
		if not valid_commit_id(revision.commit_id) or type(revision.change_id) ~= "string" then
			return nil, "jj returned a revision without stable identifiers"
		end
		if type(revision.bookmarks) ~= "table" then
			return nil, "jj returned invalid revision bookmark data"
		end
		for _, bookmark in ipairs(revision.bookmarks) do
			if type(bookmark) ~= "string" or bookmark == "" then
				return nil, "jj returned invalid revision bookmark data"
			end
		end
		table.sort(revision.bookmarks)
	end
	for _, revision in ipairs(revisions) do
		local bookmark_prefix = #revision.bookmarks > 0
				and "[" .. table.concat(revision.bookmarks, ", ") .. "] "
			or ""
		revision.display = string.format(
			"%-12s  %-12s  %s%s",
			revision.change_id:sub(1, 12),
			revision.commit_id:sub(1, 12),
			bookmark_prefix,
			display_text(revision.description)
		)
	end
	return revisions
end

--- Lists local bookmarks with at least one target and adds picker labels.
---@param repo string Repository root.
---@param runner? lib.jj_diff.Runner
---@return lib.jj_diff.Bookmark[]? bookmarks
---@return string? error
function M.list_bookmarks(repo, runner)
	local output, err = (runner or run_jj)({
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
		title = "jj revision " .. revision.change_id:sub(1, 12),
		description = revision.description,
	}
end

--- Describes the range from a bookmark's nearest first-parent bookmark to its target.
---
--- Fails when either endpoint cannot be resolved to one unambiguous commit.
---@param repo string Repository root.
---@param bookmark lib.jj_diff.Bookmark Selected bookmark.
---@param bookmarks lib.jj_diff.Bookmark[] Local bookmarks available as possible bases.
---@param runner? lib.jj_diff.Runner
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
	local output, err = (runner or run_jj)({
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
	}
end

--- Renders a comparison's diff stat.
---@param comparison lib.jj_diff.Comparison
---@param runner? lib.jj_diff.Runner
---@return string? stat
---@return string? error
function M.stat(comparison, runner)
	return (runner or run_jj)(comparison_stat_args(comparison), comparison.repo)
end

--- Renders a comparison's preview summary, including its revision description when available.
---@param comparison lib.jj_diff.ReviewComparison
---@param runner? lib.jj_diff.Runner
---@return string? summary
---@return string? error
function M.preview_summary(comparison, runner)
	local stat, err = M.stat(comparison, runner)
	if not stat then
		return nil, err
	end
	local description = trim(comparison.description)
	if description == "" then
		return stat
	end
	if trim(stat) == "" then
		return description
	end
	return description .. "\n\n" .. stat
end

--- Lists changed files in a comparison with display labels.
---@param comparison lib.jj_diff.Comparison
---@param runner? lib.jj_diff.Runner
---@return lib.jj_diff.ChangedFile[]? files
---@return string? error
function M.changed_files(comparison, runner)
	local output, err = (runner or run_jj)(comparison_files_args(comparison), comparison.repo)
	if not output then
		return nil, err
	end
	local files
	files, err = json_lines(output)
	if not files then
		return nil, err
	end
	for _, file in ipairs(files) do
		if
			type(file.path) ~= "string"
			or type(file.display) ~= "string"
			or type(file.status) ~= "string"
		then
			return nil, "jj returned invalid changed-file data"
		end
		file.label = string.format("%s  %s", file.status, display_text(file.display))
	end
	return files
end

--- Renders a comparison as an uncolored Git patch.
---@param comparison lib.jj_diff.Comparison
---@param path? string Optional root-relative path scope.
---@param runner? lib.jj_diff.Runner
---@return string? patch
---@return string? error
function M.patch(comparison, path, runner)
	return (runner or run_jj)(comparison_patch_args(comparison, path), comparison.repo)
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

--- Maps an old-side source location through a patch to the new-side file.
---
--- Unmentioned files retain their location. Lines outside hunks map through file renames and the
--- accumulated line offset. Deleted files and replaced or deleted lines return `nil`; copied files
--- do not redirect their source location.
---@param patch string
---@param path string Root-relative old-side path.
---@param line integer One-based old-side line number.
---@return string? path
---@return integer? line
function M.map_line(patch, path, line)
	local parsed = M.parse_patch(patch)
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

--- Resolves a working-copy line to its location in the responsible revision.
---@param repo string Repository root.
---@param path string Root-relative working-copy path.
---@param line integer One-based working-copy line number.
---@param runner? lib.jj_diff.Runner
---@return lib.jj_diff.ReviewComparison? comparison
---@return lib.jj_diff.Location|string? location_or_error
function M.resolve_line_revision(repo, path, line, runner)
	local attribution, err = M.annotate_line(repo, path, line, runner)
	if not attribution then
		return nil, err
	end
	local comparison = M.revision_comparison(repo, attribution)
	local revision_patch
	revision_patch, err = M.patch(comparison, nil, runner)
	if not revision_patch then
		return nil, err
	end
	local forward_patch
	forward_patch, err =
		M.patch({ repo = repo, from = attribution.commit_id, target = "@" }, nil, runner)
	if not forward_patch then
		return nil, err
	end

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
					M.map_line(forward_patch, candidate.path, candidate.line)
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

--- Reports a recoverable JJ diff error without interrupting Neovim.
---@param message? string
local function notify_error(message)
	vim.notify(message or "JJ diff failed", vim.log.levels.WARN)
end

--- Opens the working-copy location corresponding to a selected patch row.
---
--- The mapping is computed from the comparison target to `@`, so later renames and edits are
--- included. Navigation is refused when the destination buffer has unsaved changes.
---@param comparison lib.jj_diff.Comparison
---@param location? lib.jj_diff.Location
---@param runner? lib.jj_diff.Runner
---@return boolean opened
function M.open_working_line(comparison, location, runner)
	if not location or not location.path or not location.line then
		notify_error("Patch line has no valid working-copy target")
		return false
	end

	local output, err = (runner or run_jj)(
		comparison_patch_args({ repo = comparison.repo, from = comparison.target, target = "@" }),
		comparison.repo
	)
	if not output then
		notify_error(err)
		return false
	end
	local path, line = M.map_line(output, location.path, location.line)
	if not path or not line then
		notify_error("Patch line does not survive in the working copy")
		return false
	end

	local absolute = vim.fs.joinpath(comparison.repo, path)
	local stat = vim.uv.fs_stat(absolute)
	if not stat or stat.type ~= "file" then
		notify_error("Working-copy file does not exist: " .. path)
		return false
	end
	local bufnr = vim.fn.bufadd(absolute)
	vim.fn.bufload(bufnr)
	if vim.bo[bufnr].modified then
		notify_error("Working-copy buffer has unsaved changes: " .. path)
		return false
	end
	if line > vim.api.nvim_buf_line_count(bufnr) then
		notify_error("Mapped line is outside the working-copy file: " .. path)
		return false
	end

	vim.cmd.edit(vim.fn.fnameescape(absolute))
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	return true
end

--- Finds the shared patch buffer if it still exists.
---@return integer? buffer
local function retained_patch_buffer()
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_valid(buffer)
			and vim.api.nvim_buf_get_name(buffer) == patch_buffer_name
		then
			return buffer
		end
	end
end

--- Replaces the patch buffer's quickfix list while preserving its list identity.
---@param buffer integer
---@param title string
---@param items table[]
local function set_patch_quickfix(buffer, title, items)
	local id = vim.b[buffer].jj_diff_quickfix_id
	local list = type(id) == "number" and vim.fn.getqflist({ id = id, all = 0 }) or {}
	if list.id == id and type(list.nr) == "number" then
		vim.fn.setqflist({}, "r", { id = id, title = title, items = items })
		vim.cmd("silent chistory " .. list.nr)
		return
	end
	vim.fn.setqflist({}, " ", { title = title, items = items })
	vim.b[buffer].jj_diff_quickfix_id = vim.fn.getqflist({ id = 0 }).id
end

--- Empties the quickfix list owned by a deleted patch buffer.
---@param buffer integer
local function clear_patch_quickfix(buffer)
	local id = vim.b[buffer].jj_diff_quickfix_id
	if type(id) == "number" and vim.fn.getqflist({ id = id }).id == id then
		vim.fn.setqflist({}, "r", { id = id, items = {} })
	end
end

--- Replaces the shared review buffer with a patch that has already been generated successfully.
---@param comparison lib.jj_diff.ReviewComparison
---@param patch string
---@param runner? lib.jj_diff.Runner
---@return integer buffer
local function show_patch(comparison, patch, runner)
	local parsed = M.parse_patch(patch)
	local buffer = retained_patch_buffer()
	if not buffer then
		buffer = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_set_name(buffer, patch_buffer_name)
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = buffer,
			once = true,
			callback = function()
				clear_patch_quickfix(buffer)
			end,
		})
	elseif not vim.api.nvim_buf_is_loaded(buffer) then
		vim.fn.bufload(buffer)
	end

	vim.bo[buffer].readonly = false
	vim.bo[buffer].modifiable = true
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, parsed.lines)
	vim.bo[buffer].buftype = "nofile"
	vim.bo[buffer].bufhidden = "hide"
	vim.bo[buffer].swapfile = false
	vim.bo[buffer].filetype = "diff"
	vim.bo[buffer].modifiable = false
	vim.bo[buffer].readonly = true
	vim.b[buffer].jj_diff_comparison = comparison

	vim.keymap.set("n", "gf", function()
		M.open_working_line(comparison, parsed.rows[vim.api.nvim_win_get_cursor(0)[1]], runner)
	end, { buffer = buffer, desc = "JJ diff: Open working-copy line" })

	local items = {}
	for _, item in ipairs(parsed.quickfix) do
		table.insert(items, {
			bufnr = buffer,
			lnum = item.lnum,
			col = 1,
			text = item.text,
		})
	end
	vim.api.nvim_win_set_buf(0, buffer)
	set_patch_quickfix(buffer, comparison.title, items)
	return buffer
end

--- Opens a comparison patch in the shared read-only review buffer.
---
--- A successful refresh replaces the buffer contents and its quickfix entries in place. A failed
--- patch command leaves any retained review state unchanged.
---@param comparison lib.jj_diff.ReviewComparison
---@param path? string Optional root-relative path scope.
---@param runner? lib.jj_diff.Runner
---@return integer? buffer
---@return string? error
function M.open_patch(comparison, path, runner)
	local patch, err = M.patch(comparison, path, runner)
	if not patch then
		return nil, err
	end
	return show_patch(comparison, patch, runner)
end

--- Opens the responsible revision's file-scoped patch for one absolute working-copy location.
---@param absolute string Absolute working-copy path.
---@param line integer One-based working-copy line number.
---@param runner? lib.jj_diff.Runner
---@return boolean opened
---@return string? error
function M.open_line_revision(absolute, line, runner)
	if type(absolute) ~= "string" or absolute:sub(1, 1) ~= "/" then
		return false, "JJ line attribution requires an absolute file path"
	end
	absolute = vim.uv.fs_realpath(absolute) or vim.fs.normalize(absolute)
	local stat = vim.uv.fs_stat(absolute)
	if not stat or stat.type ~= "file" then
		return false, "JJ line attribution requires an existing file"
	end
	if type(line) ~= "number" or line < 1 or line % 1 ~= 0 then
		return false, "JJ line attribution requires a positive line number"
	end
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		local buffer_name = vim.api.nvim_buf_get_name(buffer)
		local buffer_path = vim.uv.fs_realpath(buffer_name) or vim.fs.normalize(buffer_name)
		if
			vim.api.nvim_buf_is_loaded(buffer)
			and buffer_path == absolute
			and vim.bo[buffer].modified
		then
			return false, "Save the buffer before opening its JJ line revision"
		end
	end

	local repo, err = M.repo_root(vim.fs.dirname(absolute), runner)
	if not repo then
		return false, err
	end
	repo = vim.uv.fs_realpath(repo) or vim.fs.normalize(repo)
	local path = vim.fs.relpath(repo, absolute)
	if not path or path == "." or path:match("^%.%.[/\\]") then
		return false, "File is outside the JJ repository"
	end
	local comparison, location_or_error = M.resolve_line_revision(repo, path, line, runner)
	if not comparison then
		return false, location_or_error
	end
	local location = location_or_error --[[@as lib.jj_diff.Location]]
	local patch
	patch, err = M.patch(comparison, location.path, runner)
	if not patch then
		return false, err
	end
	local parsed = M.parse_patch(patch)
	local row
	for candidate_row, candidate in pairs(parsed.rows) do
		if candidate.path == location.path and candidate.line == location.line then
			if row then
				return false, "Attributed line appears ambiguously in its revision patch"
			end
			row = candidate_row
		end
	end
	if not row then
		for _, file in ipairs(parsed.files) do
			if
				file.old_path
				and file.new_path == location.path
				and file.old_path ~= file.new_path
				and not file.copy
			then
				row = file.row
				break
			end
		end
	end
	if not row then
		return false, "Attributed line is missing from its revision patch"
	end

	show_patch(comparison, patch, runner)
	vim.api.nvim_win_set_cursor(0, { row, 0 })
	return true
end

--- Opens the responsible revision for the current cursor line.
---@return boolean opened
function M.open_cursor_revision()
	local buffer = vim.api.nvim_get_current_buf()
	if vim.bo[buffer].buftype ~= "" then
		notify_error("JJ line attribution requires a file buffer")
		return false
	end
	local absolute = vim.api.nvim_buf_get_name(buffer)
	if absolute == "" then
		notify_error("JJ line attribution requires a named file buffer")
		return false
	end
	local opened, err = M.open_line_revision(absolute, vim.api.nvim_win_get_cursor(0)[1])
	if not opened then
		notify_error(err)
	end
	return opened
end

--- Reopens scope selection for the comparison retained by the patch buffer.
function M.pick_retained_scope()
	local buffer = retained_patch_buffer()
	if not buffer then
		notify_error("No retained jj patch buffer")
		return
	end
	local comparison = vim.b[buffer].jj_diff_comparison
	if type(comparison) ~= "table" then
		notify_error("Retained jj patch has no comparison context")
		return
	end
	M.pick_scope(comparison)
end

--- Creates an fzf-lua previewer backed by exact source-entry lookup.
---@param entry_map table<string, any>
---@param preview lib.jj_diff.Preview
---@return table previewer_spec
local function previewer(entry_map, preview)
	local class = require("fzf-lua.previewer.builtin").base:extend()

	--- Populates the preview buffer for an encoded picker entry.
	---@param entry string
	function class:populate_preview_buf(entry)
		local content, err, title, filetype = preview(entry_map[entry])
		local buffer = self:get_tmp_buffer()
		local lines = content and patch_lines(content) or { err or "Unable to preview selection" }
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
		vim.bo[buffer].filetype = content and filetype or ""
		self:set_preview_buf(buffer)
		self.win:update_preview_title(title or "jj diff error")
	end

	return {
		_ctor = function()
			return class
		end,
	}
end

--- Encodes picker entries with stable unique prefixes and a reverse lookup.
---@param entries lib.jj_diff.PickerEntry[]
---@return string[] source
---@return table<string, lib.jj_diff.PickerEntry> entry_map
local function picker_entries(entries)
	local source = {}
	local entry_map = {}
	for index, item in ipairs(entries) do
		local entry = string.format("%06d\t%s", index, item.display)
		table.insert(source, entry)
		entry_map[entry] = item
	end
	return source, entry_map
end

--- Opens file-scope selection for a comparison and previews patches or the aggregate stat.
---@param comparison lib.jj_diff.ReviewComparison
function M.pick_scope(comparison)
	local files, err = M.changed_files(comparison)
	if not files then
		notify_error(err)
		return
	end
	local entries = { { display = "[all files]" } }
	for _, file in ipairs(files) do
		table.insert(entries, { display = file.label, path = file.path })
	end
	local source, entry_map = picker_entries(entries)

	require("fzf-lua").fzf_exec(source, {
		prompt = "JJ diff scope> ",
		fzf_opts = {
			["--delimiter"] = "\t",
			["--with-nth"] = "2..",
		},
		previewer = function()
			return previewer(entry_map, function(item)
				if item.path then
					local patch, patch_err = M.patch(comparison, item.path)
					return patch, patch_err, comparison.title .. " / " .. item.path, "diff"
				end
				local stat, stat_err = M.stat(comparison)
				return stat, stat_err, comparison.title .. " / all files", ""
			end)
		end,
		actions = {
			["default"] = function(selected)
				local item = entry_map[selected[1]]
				if not item then
					return
				end
				local _, open_err = M.open_patch(comparison, item.path)
				if open_err then
					notify_error(open_err)
				end
			end,
		},
	})
end

--- Opens a comparison picker and hands the selected comparison to scope selection.
---@param entries lib.jj_diff.PickerEntry[]
---@param prompt string
---@param resolve lib.jj_diff.Resolve
local function picker(entries, prompt, resolve)
	if #entries == 0 then
		notify_error("No jj entries available")
		return
	end
	local source, entry_map = picker_entries(entries)

	require("fzf-lua").fzf_exec(source, {
		prompt = prompt,
		fzf_opts = {
			["--delimiter"] = "\t",
			["--with-nth"] = "2..",
		},
		previewer = function()
			return previewer(entry_map, function(item)
				local comparison, err = resolve(item)
				if not comparison then
					return nil, err
				end
				local summary
				summary, err = M.preview_summary(comparison)
				return summary, err, comparison.title, ""
			end)
		end,
		actions = {
			["default"] = function(selected)
				local comparison, err = resolve(entry_map[selected[1]])
				if not comparison then
					notify_error(err)
					return
				end
				M.pick_scope(comparison)
			end,
		},
	})
end

--- Opens revision selection for the repository containing Neovim's working directory.
function M.pick_revision()
	local repo, err = M.repo_root()
	if not repo then
		notify_error(err)
		return
	end
	local revisions
	revisions, err = M.list_revisions(repo)
	if not revisions then
		notify_error(err)
		return
	end
	picker(revisions, "JJ revision diff> ", function(revision)
		return M.revision_comparison(repo, revision)
	end)
end

--- Opens bookmark-range selection for the repository containing Neovim's working directory.
function M.pick_bookmark()
	local repo, err = M.repo_root()
	if not repo then
		notify_error(err)
		return
	end
	local bookmarks
	bookmarks, err = M.list_bookmarks(repo)
	if not bookmarks then
		notify_error(err)
		return
	end
	picker(bookmarks, "JJ bookmark diff> ", function(bookmark)
		return M.bookmark_comparison(repo, bookmark, bookmarks)
	end)
end

return M
