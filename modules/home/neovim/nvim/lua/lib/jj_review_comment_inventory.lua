--- Finds every JJ change with stored review comments in a repository, classifies whether each
--- change is still reviewable, and browses or prunes those comment stores.
---@class lib.jj_review_comment_inventory
local M = {}
local history = require("lib.jj_history")
local jj_id = require("lib.jj_id")
local review_comments = require("lib.jj_review_comments")

---@alias lib.jj_review_comment_inventory.ChangeState
---| "open" The change is visible and mutable.
---| "landed" The change is visible but immutable, such as after merging into trunk.
---| "gone" No visible revision has the change ID, such as after abandoning or squashing it.
---| "unreadable" The comment store is malformed, so its comments cannot be counted.

---@class lib.jj_review_comment_inventory.Entry
---@field change_id string
---@field state lib.jj_review_comment_inventory.ChangeState
---@field comments lib.jj_review_comments.Comment[] Empty when the store is unreadable.
---@field revision? lib.jj_history.Revision Newest visible revision of the change.

local revision_template = '"[" ++ json(self) ++ "," ++ json(immutable) ++ "]\\n"'

local function display(value)
	return (value:match("^[^\r\n]*") or ""):gsub("[%c]", " ")
end

--- Summarizes an entry on one line for pickers and confirmation prompts.
---@param entry lib.jj_review_comment_inventory.Entry
---@return string
local function describe(entry)
	local count = #entry.comments
	local summary = entry.revision and display(entry.revision.description)
		or "(change no longer exists)"
	return string.format(
		"%-12s %s  %s  %s",
		"[" .. entry.state .. "]",
		jj_id.short(entry.change_id),
		entry.state == "unreadable" and "malformed store"
			or (count .. (count == 1 and " comment" or " comments")),
		summary ~= "" and summary or "(no description set)"
	)
end

---@param repo string
---@param entry lib.jj_review_comment_inventory.Entry
---@return string[]
local function preview_lines(repo, entry)
	local lines = { describe(entry), "" }
	if entry.state == "unreadable" then
		lines[#lines + 1] = "Cannot read " .. review_comments.store_path(repo, entry.change_id)
		return lines
	end
	for _, comment in ipairs(entry.comments) do
		lines[#lines + 1] = "## "
			.. display(comment.path)
			.. ":"
			.. review_comments.line_label(comment.lines)
		lines[#lines + 1] = ""
		vim.list_extend(lines, vim.split(vim.trim(comment.body), "\n", { plain = true }))
		lines[#lines + 1] = ""
	end
	return lines
end

--- Deletes an entry's comment store and refreshes any review showing that change.
---@param repo string
---@param entry lib.jj_review_comment_inventory.Entry
local function delete(repo, entry)
	local err = review_comments.save(repo, entry.change_id, {})
	if err then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end
	require("lib.jj_review").reload_comments(repo, entry.change_id)
end

--- Resolves the JJ root of the current file's directory, or of cwd for non-file buffers.
---@return string? repo
local function current_repo()
	local file = vim.api.nvim_buf_get_name(0)
	local cwd = vim.bo.buftype == "" and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
	local repo, err = history.run({ "root" }, cwd)
	if not repo then
		vim.notify(err, vim.log.levels.ERROR)
		return nil
	end
	return (repo:gsub("\n$", ""))
end

--- Lists the repository's comment stores, newest-first in JJ log order with gone changes last.
---@param repo string Repository root.
---@return lib.jj_review_comment_inventory.Entry[]? entries
---@return string? err
function M.list(repo)
	local entries, by_change, change_ids = {}, {}, {}
	local directory = review_comments.repo_store_directory(repo)
	if not vim.uv.fs_stat(directory) then
		return entries
	end
	for name, kind in vim.fs.dir(directory) do
		local change_id = kind == "file" and name:match("^(%l+)%.json$")
		if change_id then
			local comments = review_comments.load(repo, change_id)
			local entry = {
				change_id = change_id,
				state = comments and "gone" or "unreadable",
				comments = comments or {},
			}
			entries[#entries + 1] = entry
			by_change[change_id] = entry
			change_ids[#change_ids + 1] = "present(change_id(" .. change_id .. "))"
		end
	end
	if #entries == 0 then
		return entries
	end

	local output, err = history.run({
		"log",
		"--no-graph",
		"--revisions",
		table.concat(change_ids, " | "),
		"--template",
		revision_template,
	}, repo)
	if not output then
		return nil, err
	end
	local order, position = {}, 0
	for line in output:gmatch("[^\r\n]+") do
		local ok, row = pcall(vim.json.decode, line)
		local revision = ok and type(row) == "table" and row[1]
		if
			type(revision) ~= "table"
			or type(revision.change_id) ~= "string"
			or type(revision.commit_id) ~= "string"
			or type(revision.description) ~= "string"
			or type(row[2]) ~= "boolean"
		then
			return nil, "JJ returned invalid revision data"
		end
		-- Divergent changes list several revisions; the first in log order is the newest.
		local entry = by_change[revision.change_id]
		if entry and not entry.revision then
			entry.revision = revision
			position = position + 1
			order[revision.change_id] = position
			if entry.state ~= "unreadable" then
				entry.state = row[2] and "landed" or "open"
			end
		end
	end

	table.sort(entries, function(a, b)
		local a_order, b_order = order[a.change_id] or math.huge, order[b.change_id] or math.huge
		if a_order ~= b_order then
			return a_order < b_order
		end
		return a.change_id < b.change_id
	end)
	return entries
end

--- Deletes the comment stores of gone changes, and of landed changes when requested, after
--- confirmation. Unreadable stores are never pruned.
---@param repo string
---@param include_landed? boolean
function M.prune(repo, include_landed)
	local entries, err = M.list(repo)
	if not entries then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end
	local doomed, lines = {}, {}
	for _, entry in ipairs(entries) do
		if entry.state == "gone" or (include_landed and entry.state == "landed") then
			doomed[#doomed + 1] = entry
			lines[#lines + 1] = describe(entry)
		end
	end
	if #doomed == 0 then
		vim.notify(
			include_landed and "No gone or landed changes have review comments"
				or "No gone changes have review comments",
			vim.log.levels.INFO
		)
		return
	end

	local question = "Delete review comments for "
		.. #doomed
		.. " changes?\n\n"
		.. table.concat(lines, "\n")
	if vim.fn.confirm(question, "&Delete\n&Cancel", 2) ~= 1 then
		return
	end
	for _, entry in ipairs(doomed) do
		delete(repo, entry)
	end
	vim.notify("Deleted review comments for " .. #doomed .. " changes")
end

--- Browses commented changes: Enter opens a review, Ctrl-X deletes a change's comments.
---@param repo string
function M.pick(repo)
	local entries, err = M.list(repo)
	if not entries then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end
	if #entries == 0 then
		vim.notify("No JJ changes in this repository have review comments", vim.log.levels.INFO)
		return
	end

	local lines, lookup = {}, {}
	for index, entry in ipairs(entries) do
		local line = string.format("%03d\t%s", index, describe(entry))
		lines[#lines + 1] = line
		lookup[line] = entry
	end
	local function selected_action(action)
		return function(selected)
			local entry = lookup[selected[1]]
			if entry then
				action(entry)
			end
		end
	end

	require("fzf-lua").fzf_exec(lines, {
		prompt = "JJ review comments> ",
		fzf_opts = {
			["--delimiter"] = "\t",
			["--with-nth"] = "2..",
			["--header"] = "Enter: open review  Ctrl-X: delete comments  Ctrl-Y: copy change ID",
		},
		previewer = function()
			local class = require("fzf-lua.previewer.builtin").base:extend()
			function class:populate_preview_buf(line)
				local entry = lookup[line]
				if not entry then
					return
				end
				local buffer = self:get_tmp_buffer()
				vim.api.nvim_buf_set_lines(buffer, 0, -1, false, preview_lines(repo, entry))
				vim.bo[buffer].filetype = "markdown"
				self:set_preview_buf(buffer)
			end
			return {
				_ctor = function()
					return class
				end,
			}
		end,
		actions = function()
			return {
				["enter"] = selected_action(function(entry)
					if not entry.revision then
						vim.notify(
							"Change "
								.. jj_id.short(entry.change_id)
								.. " no longer exists; Ctrl-X deletes its comments",
							vim.log.levels.WARN
						)
						return
					end
					require("lib.jj_review").open(repo, entry.revision)
				end),
				["ctrl-x"] = selected_action(function(entry)
					local question = "Delete review comments for " .. describe(entry) .. "?"
					if vim.fn.confirm(question, "&Delete\n&Cancel", 2) == 1 then
						delete(repo, entry)
					end
					M.pick(repo)
				end),
				["ctrl-y"] = selected_action(function(entry)
					vim.fn.setreg("+", entry.change_id)
				end),
			}
		end,
	})
end

--- Browses commented changes in the current file's repository, falling back to cwd.
function M.pick_current()
	local repo = current_repo()
	if repo then
		M.pick(repo)
	end
end

--- Prunes comment stores in the current file's repository, falling back to cwd.
---@param include_landed? boolean
function M.prune_current(include_landed)
	local repo = current_repo()
	if repo then
		M.prune(repo, include_landed)
	end
end

return M
