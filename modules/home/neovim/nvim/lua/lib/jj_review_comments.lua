--- Persists JJ review comments per change, re-anchors them to rendered diff rows, and composes
--- agent review prompts from them.
---@class lib.jj_review_comments
local M = {}

---@alias lib.jj_review_comments.Side "old"|"new" Diff side whose line numbers a line uses.

---@class lib.jj_review_comments.Line A commented diff line as it appeared when written.
---@field side lib.jj_review_comments.Side Deleted lines are old-side; others are new-side.
---@field kind "context"|"add"|"delete"
---@field line integer Line number on `side`.
---@field text string

---@class lib.jj_review_comments.Comment
---@field id string Stable identifier within the change's comment store.
---@field path string Root-relative path of the commented file.
---@field commit_id string Target commit whose diff the comment's lines were taken from.
---@field lines lib.jj_review_comments.Line[] Contiguous source lines in diff order; never empty.
---@field body string Markdown review text.

---@alias lib.jj_review_comments.Placement
---| "current" Anchored in the commit it was written against.
---| "carried" Anchored by matching text after the change was rewritten.
---| "stale" The commented lines no longer appear in the file's complete diff.
---| "outside" The commented file is no longer part of the comparison.
---| "unloaded" The file's diff is collapsed or paged, so the anchor is unverified.

---@class lib.jj_review_comments.Located
---@field comment lib.jj_review_comments.Comment
---@field placement lib.jj_review_comments.Placement
---@field first_row? integer First rendered row of an anchored comment.
---@field last_row? integer Last rendered row of an anchored comment.
---@field lines lib.jj_review_comments.Line[] Current lines when anchored, otherwise as written.

---@class lib.jj_review_comments.FileView Rendered state of one file in the comparison.
---@field rows integer[] Rendered source rows of the file's loaded page, in diff order.
---@field complete boolean Whether `rows` cover the file's entire diff.

---@class lib.jj_review_comments.View
---@field commit_id string Target commit of the rendered comparison.
---@field rendered lib.jj_diff_render.Result
---@field files? table<string, lib.jj_review_comments.FileView> Absent until the file list loads.

---@class lib.jj_review_comments.PromptContext
---@field change_id string
---@field commit_id string Target commit of the comparison.
---@field diff_command string Shell command that reproduces the reviewed diff.

local store_version = 1

--- Directory holding comment stores; tests replace it with a disposable directory.
---@return string
function M.store_directory()
	return vim.fs.joinpath(vim.fn.stdpath("data"), "jj-review", "comments")
end

--- Returns the comment store file for a repository's change.
---@param repo string Repository root.
---@param change_id string
---@return string
function M.store_path(repo, change_id)
	local key = vim.fs.basename(repo):gsub("[^%w._-]", "_") .. "-" .. vim.fn.sha256(repo):sub(1, 12)
	return vim.fs.joinpath(M.store_directory(), key, change_id .. ".json")
end

local function valid_store(store)
	if
		type(store) ~= "table"
		or store.version ~= store_version
		or type(store.comments) ~= "table"
	then
		return false
	end
	for _, comment in ipairs(store.comments) do
		if
			type(comment) ~= "table"
			or type(comment.id) ~= "string"
			or type(comment.path) ~= "string"
			or type(comment.commit_id) ~= "string"
			or type(comment.body) ~= "string"
			or type(comment.lines) ~= "table"
			or #comment.lines == 0
		then
			return false
		end
		for _, line in ipairs(comment.lines) do
			if
				type(line) ~= "table"
				or (line.side ~= "old" and line.side ~= "new")
				or type(line.kind) ~= "string"
				or type(line.line) ~= "number"
				or type(line.text) ~= "string"
			then
				return false
			end
		end
	end
	return true
end

--- Reads a change's comments. A missing store is empty; a malformed store is an error so callers
--- never overwrite comments they could not read.
---@param repo string
---@param change_id string
---@return lib.jj_review_comments.Comment[]? comments
---@return string? err
function M.load(repo, change_id)
	local path = M.store_path(repo, change_id)
	if not vim.uv.fs_stat(path) then
		return {}
	end

	local ok, content = pcall(vim.fn.readfile, path, "b")
	if not ok then
		return nil, "Cannot read review comments: " .. path
	end
	local decoded_ok, store = pcall(vim.json.decode, table.concat(content, "\n"))
	if not decoded_ok or not valid_store(store) then
		return nil, "Malformed review comments: " .. path
	end
	return store.comments
end

--- Replaces a change's comments atomically; an empty list removes the store.
---@param repo string
---@param change_id string
---@param comments lib.jj_review_comments.Comment[]
---@return string? err
function M.save(repo, change_id, comments)
	local path = M.store_path(repo, change_id)
	if #comments == 0 then
		local ok, err = vim.uv.fs_unlink(path)
		if not ok and not tostring(err):match("^ENOENT") then
			return "Cannot remove review comments: " .. tostring(err)
		end
		return nil
	end

	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local temporary = path .. ".tmp." .. vim.uv.os_getpid()
	local encoded = vim.json.encode({
		version = store_version,
		change_id = change_id,
		comments = comments,
	})
	if vim.fn.writefile({ encoded }, temporary, "b") ~= 0 then
		return "Cannot write review comments: " .. temporary
	end
	local ok, err = vim.uv.fs_rename(temporary, path)
	if not ok then
		vim.uv.fs_unlink(temporary)
		return "Cannot save review comments: " .. tostring(err)
	end
end

--- Returns a new identifier unique within a change's store.
---@return string
function M.new_id()
	return string.format("%x-%04x", vim.uv.hrtime(), math.random(0, 0xffff))
end

---@param row lib.jj_diff_render.Line
---@return lib.jj_review_comments.Line
local function source_line(row)
	local side = row.kind == "delete" and "old" or "new"
	return {
		side = side,
		kind = row.kind,
		line = side == "old" and row.old_line or row.new_line,
		text = row.text,
	}
end

--- Reports whether a rendered row is a commentable source line.
---@param row? lib.jj_diff_render.Line
---@return boolean
function M.is_source_row(row)
	return row ~= nil
		and row.path ~= nil
		and (row.kind == "context" or row.kind == "add" or row.kind == "delete")
end

--- Converts rendered rows into comment lines, skipping hunk headers and metadata between them.
---@param rows table<integer, lib.jj_diff_render.Line> Rendered rows keyed by row number.
---@param numbers integer[] Row numbers in diff order.
---@return lib.jj_review_comments.Line[]? lines
---@return string? path
---@return string? err
function M.anchor_lines(rows, numbers)
	local lines, path = {}, nil
	for _, number in ipairs(numbers) do
		local row = rows[number]
		if M.is_source_row(row) then
			if path and row.path ~= path then
				return nil, nil, "Review comments cannot span files"
			end
			path = row.path
			lines[#lines + 1] = source_line(row)
		end
	end
	if not path then
		return nil, nil, "Select a diff source line to comment on"
	end
	return lines, path
end

--- Returns how far a candidate run starts from the comment's original line, or nil on mismatch.
local function match_distance(rows, file_rows, start, lines)
	for offset, expected in ipairs(lines) do
		local actual = source_line(rows[file_rows[start + offset - 1]])
		if actual.side ~= expected.side or actual.text ~= expected.text then
			return nil
		end
	end
	return math.abs(source_line(rows[file_rows[start]]).line - lines[1].line)
end

---@param comment lib.jj_review_comments.Comment
---@param view lib.jj_review_comments.View
---@return lib.jj_review_comments.Located
local function locate_comment(comment, view)
	local result = {
		comment = comment,
		lines = comment.lines,
	}
	local file = view.files and view.files[comment.path]
	if not view.files then
		result.placement = "unloaded"
		return result
	end
	if not file then
		result.placement = "outside"
		return result
	end

	local best_start, best_distance
	local count = #comment.lines
	for start = 1, #file.rows - count + 1 do
		local distance = match_distance(view.rendered.rows, file.rows, start, comment.lines)
		if distance and (not best_distance or distance < best_distance) then
			best_start, best_distance = start, distance
		end
	end

	if not best_start then
		result.placement = file.complete and "stale" or "unloaded"
		return result
	end
	result.first_row = file.rows[best_start]
	result.last_row = file.rows[best_start + count - 1]
	result.lines = M.anchor_lines(
		view.rendered.rows,
		{ unpack(file.rows, best_start, best_start + count - 1) }
	)
	result.placement = comment.commit_id == view.commit_id and "current" or "carried"
	return result
end

--- Places every comment against the rendered comparison, preferring the nearest exact match.
---@param comments lib.jj_review_comments.Comment[]
---@param view lib.jj_review_comments.View
---@return lib.jj_review_comments.Located[]
function M.locate(comments, view)
	local located = {}
	for _, comment in ipairs(comments) do
		located[#located + 1] = locate_comment(comment, view)
	end
	return located
end

local function longest_backtick_run(value)
	local longest = 0
	for run in value:gmatch("`+") do
		longest = math.max(longest, #run)
	end
	return longest
end

--- Labels new-side line ranges, falling back to old-side ranges for pure deletions.
---@param lines lib.jj_review_comments.Line[]
---@return string
function M.line_label(lines)
	for _, side in ipairs({ "new", "old" }) do
		local first, last
		for _, line in ipairs(lines) do
			if line.side == side then
				first = first or line.line
				last = line.line
			end
		end
		if first then
			local range = first == last and tostring(first) or (first .. "-" .. last)
			return side == "new" and range or (range .. " (removed lines)")
		end
	end
	return "?"
end

---@param number integer
---@param item lib.jj_review_comments.Located
---@param outdated boolean
---@return string
local function prompt_section(number, item, outdated)
	local quoted = {}
	for _, line in ipairs(item.lines) do
		local prefix = line.kind == "add" and "+" or (line.kind == "delete" and "-" or " ")
		quoted[#quoted + 1] = prefix .. line.text
	end
	local code = table.concat(quoted, "\n")
	local fence = string.rep("`", math.max(3, longest_backtick_run(code) + 1))

	return "## "
		.. number
		.. ". "
		.. item.comment.path
		.. ":"
		.. M.line_label(item.lines)
		.. (outdated and " (outdated)" or "")
		.. "\n\n"
		.. fence
		.. "diff\n"
		.. code
		.. "\n"
		.. fence
		.. "\n\n"
		.. vim.trim(item.comment.body)
end

--- Composes a Markdown prompt asking an agent to address the located comments.
--- Stale and outside comments are omitted unless `include_stale` is set.
---@param context lib.jj_review_comments.PromptContext
---@param located lib.jj_review_comments.Located[] Comments in presentation order.
---@param include_stale? boolean
---@return string? prompt Nil when no comments qualify.
function M.compose_prompt(context, located, include_stale)
	local sections = {}
	for _, item in ipairs(located) do
		local outdated = item.placement == "stale" or item.placement == "outside"
		if include_stale or not outdated then
			sections[#sections + 1] = prompt_section(#sections + 1, item, outdated)
		end
	end
	if #sections == 0 then
		return nil
	end

	local header = {
		"Address these review comments on JJ change "
			.. context.change_id
			.. " (commit "
			.. context.commit_id
			.. ").",
		"Inspect the reviewed diff with `" .. context.diff_command .. "`.",
		"Each comment quotes the diff lines it refers to; line numbers are from that diff.",
	}
	if include_stale then
		header[#header + 1] = "Comments marked outdated quote code that has since changed;"
			.. " check whether they still apply before acting on them."
	end
	return table.concat(header, "\n") .. "\n\n" .. table.concat(sections, "\n\n") .. "\n"
end

return M
