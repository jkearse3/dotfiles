--- Traces recorded file identity through conservative, metadata-only rename transitions.
local M = {}

---@class lib.jj_file_history.Result
---@field revisions lib.jj_history.Revision[] Newest first; each carries its historical path.
---@field boundary string Why traversal ended; never implies unexamined history is complete.

local history_template =
	'"[" ++ json(self) ++ "," ++ json(local_bookmarks.map(|b| b.name())) ++ "]\\n"'
local diff_template =
	'"{\\"status\\":" ++ json(status) ++ ",\\"source\\":" ++ json(stringify(source.path())) ++ ",\\"target\\":" ++ json(stringify(target.path())) ++ "}\\n"'

local function decode_rows(output)
	local rows = {}
	for line in output:gmatch("[^\r\n]+") do
		local ok, row = pcall(vim.json.decode, line)
		if not ok or type(row) ~= "table" then
			return nil, "JJ returned invalid file-history metadata"
		end
		rows[#rows + 1] = row
	end
	return rows
end

local function decode_revision(row)
	local revision, bookmarks = row[1], row[2]
	if
		type(revision) ~= "table"
		or type(revision.commit_id) ~= "string"
		or not revision.commit_id:match("^%x+$")
		or type(revision.change_id) ~= "string"
		or type(revision.description) ~= "string"
		or type(revision.parents) ~= "table"
		or type(bookmarks) ~= "table"
	then
		return nil, "JJ returned invalid file-history revision"
	end
	for _, name in ipairs(bookmarks) do
		if type(name) ~= "string" then
			return nil, "JJ returned invalid file-history bookmarks"
		end
	end
	for _, parent in ipairs(revision.parents) do
		if type(parent) ~= "string" or not parent:match("^%x+$") then
			return nil, "JJ returned invalid file-history parent"
		end
	end
	revision.bookmarks = bookmarks
	return revision
end

local function transition(output, path)
	local changes, err = decode_rows(output)
	if not changes then
		return nil, nil, err
	end
	local selected, candidates = nil, 0
	for _, change in ipairs(changes) do
		if
			type(change.source) ~= "string"
			or type(change.target) ~= "string"
			or not vim.tbl_contains(
				{ "added", "removed", "modified", "renamed", "copied" },
				change.status
			)
		then
			return nil, nil, "JJ returned invalid file-history transition"
		end
		if change.status == "removed" or change.status == "renamed" then
			candidates = candidates + 1
		end
		if change.target == path then
			if selected then
				return nil, nil, "JJ returned duplicate file-history paths"
			end
			selected = change
		end
	end
	return selected, candidates
end

--- Follows single-parent history, accepting detected renames only when that commit has one
--- removed/renamed source. Rename identity remains heuristic. Queries never request patch bodies.
--- The injected runner must pin one operation, bound output, and support yielding. Unchanged
--- commits are skipped by JJ's files revset; merge boundaries are deliberately kept in the log.
--- Stops at additions, merges, competing sources, 500 candidate commits, 200 entries, or a
--- 30-second budget checked between candidates. Query failures discard partial results.
---@param path string Exact recorded root-relative path.
---@param run fun(args: string[]): string?, string?
---@return lib.jj_file_history.Result? result
---@return string? error
function M.trace(path, run)
	local started, inspected = vim.uv.hrtime(), 0
	local fileset = require("lib.jj_review_source").fileset
	local present, err =
		run({ "file", "list", "-r", "@", "-T", '"present\\n"', "--", fileset(path) })
	if not present then
		return nil, err
	end
	if present == "" then
		return nil,
			"File is absent from recorded JJ @; record new files/renames before browsing their history"
	end

	local result = { revisions = {}, boundary = "No earlier matching history found" }
	local cursor = "@"
	while cursor do
		local output
		output, err = run({
			"log",
			"--no-graph",
			"--limit",
			"501",
			"-r",
			"first_ancestors(" .. cursor .. ") & (files(" .. fileset(path) .. ") | merges())",
			"-T",
			history_template,
		})
		if not output then
			return nil, err
		end
		local history
		history, err = decode_rows(output)
		if not history then
			return nil, err
		end
		cursor = nil
		for _, row in ipairs(history) do
			if inspected >= 500 or #result.revisions >= 200 or vim.uv.hrtime() - started > 30e9 then
				result.boundary =
					"Partial history: reached the 500-candidate / 200-entry / 30-second lookup limit"
				return result
			end
			local revision
			revision, err = decode_revision(row)
			if not revision then
				return nil, err
			end
			inspected = inspected + 1
			if #revision.parents == 0 then
				return result
			end
			if #revision.parents ~= 1 then
				result.boundary = "Partial history: stopped at merge "
					.. revision.commit_id:sub(1, 12)
					.. "; parent lineage is not inferred"
				return result
			end
			local parent = revision.parents[1]
			output, err =
				run({ "diff", "--from", parent, "--to", revision.commit_id, "-T", diff_template })
			if not output then
				return nil, err
			end
			local selected, candidates
			selected, candidates, err = transition(output, path)
			if err then
				return nil, err
			end
			if selected then
				revision.path = path
				result.revisions[#result.revisions + 1] = revision
				if selected.status == "added" then
					result.boundary = "Added at "
						.. revision.commit_id:sub(1, 12)
						.. "; older identity (including undetected renames/copies) is not inferred"
					return result
				elseif selected.status == "renamed" then
					if candidates ~= 1 then
						result.boundary = "Partial history: competing rename sources at "
							.. revision.commit_id:sub(1, 12)
							.. "; older filename is not inferred"
						return result
					end
					path, cursor = selected.source, "commit_id(" .. parent .. ")"
					break
				elseif selected.status ~= "modified" then
					result.boundary = "Partial history: stopped at "
						.. selected.status
						.. " transition "
						.. revision.commit_id:sub(1, 12)
					return result
				end
			end
		end
	end
	return result
end

return M
