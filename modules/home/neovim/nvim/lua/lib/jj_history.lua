local M = {}

---@class lib.jj_history.Revision
---@field commit_id string Exact version, including hidden evolutionary predecessors.
---@field change_id string Stable change identity.
---@field description string
---@field bookmarks string[]
---@field recorded_at? string Committer timestamp of this recorded draft, including timezone.
---@field has_predecessors? boolean Present on evolution entries; false identifies an initial draft.

--- Runs inspection without snapshotting files, importing Git refs, or advancing the operation log.
---@param args string[]
---@param repo? string
---@return string? output
---@return string? error
function M.run(args, repo)
	local command =
		{ "jj", "--at-operation=@", "--ignore-working-copy", "--no-pager", "--color", "never" }
	vim.list_extend(command, args)
	local ok, result = pcall(function()
		return vim.system(command, { cwd = repo, text = true }):wait(10000)
	end)
	if not ok then
		return nil,
			"JJ unavailable: "
				.. tostring(result)
				.. "\nUse Git history/blame: glh / glf / gbl / gbf"
	end
	if result.code ~= 0 then
		return nil,
			vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr)
				or "JJ inspection failed (exit " .. result.code .. ")"
	end
	return result.stdout or ""
end

--- JJ quoted strings do not accept JSON's Unicode escapes; retain other bytes literally.
local function literal_fileset(path)
	local escapes =
		{ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
	return 'root-file:"' .. path:gsub('["\\\n\r\t]', escapes) .. '"'
end

local revision_template =
	'"[" ++ json(self) ++ "," ++ json(local_bookmarks.map(|b| b.name())) ++ "]\\n"'

--- Lists JJ's configured default log selection, capped at 200 revisions in topology order.
---@param repo string
---@return lib.jj_history.Revision[]? revisions
---@return string? error
---@param evolution? string Commit/revset whose evolutionary predecessors to list instead.
---@param path? string Exact root-relative path; limits history to workspace ancestry, without rename following.
function M.list(repo, evolution, path)
	local args = { "log", "--no-graph", "--limit", "200", "--template", revision_template }
	if evolution then
		local template = '"[" ++ json(commit) ++ "," ++ json(commit.local_bookmarks().map(|b| b.name()))'
			.. ' ++ "," ++ json(predecessors.len() > 0) ++ "]\\n"'
		args = {
			"evolog",
			"--no-graph",
			"--limit",
			"200",
			"--revisions",
			evolution,
			"--template",
			template,
		}
	end
	if path then
		vim.list_extend(args, { "-r", "::@", "--", literal_fileset(path) })
	end
	local output, err = M.run(args, repo)
	if not output then
		return nil, err
	end
	local revisions = {}
	for line in output:gmatch("[^\r\n]+") do
		local ok, row = pcall(vim.json.decode, line)
		if
			not ok
			or type(row) ~= "table"
			or type(row[1]) ~= "table"
			or type(row[1].commit_id) ~= "string"
			or not row[1].commit_id:match("^%x+$")
			or type(row[1].change_id) ~= "string"
			or type(row[1].description) ~= "string"
			or type(row[2]) ~= "table"
		then
			return nil, "JJ returned invalid history data"
		end
		row[1].bookmarks = row[2]
		if evolution then
			if type(row[3]) ~= "boolean" then
				return nil, "JJ returned invalid draft data"
			end
			row[1].has_predecessors = row[3]
		end
		if type(row[1].committer) == "table" and type(row[1].committer.timestamp) == "string" then
			row[1].recorded_at = row[1].committer.timestamp
		end
		revisions[#revisions + 1] = row[1]
	end
	return revisions
end

-- Ask evolog for the actual predecessors, not the adjacent row in the flattened picker.
local draft_template = table.concat({
	'"Previous drafts of this change\\nChange: " ++ commit.change_id()',
	' ++ "\\nSelected draft: " ++ commit.commit_id()',
	' ++ "\\nRecorded: " ++ commit.committer().timestamp()',
	' ++ "\\n" ++ if(predecessors.len() == 0, "No earlier recorded draft to compare.\\n",',
	' "Comparison: earlier draft(s) -> selected draft\\nEarlier draft(s): "',
	' ++ predecessors.map(|p| p.commit_id().short()).join(", ")',
	' ++ "\\nRebase-only parent changes are excluded.\\n")',
	' ++ "\\n" ++ commit.description() ++ "\\n"',
})

--- Returns metadata and the parent-relative patch for an exact commit version.
---@param repo string
---@param revision lib.jj_history.Revision
---@return string? patch
---@return string? error
---@param evolution? string Inspect the version's predecessor-relative interdiff when set.
---@param path? string Scope the parent-relative patch to this exact root-relative path.
function M.patch(repo, revision, evolution, path)
	if evolution then
		if revision.has_predecessors == false then
			return "Previous drafts of this change\nChange: "
				.. revision.change_id
				.. "\nSelected draft: "
				.. revision.commit_id
				.. "\nRecorded: "
				.. (revision.recorded_at or "time unavailable")
				.. "\nNo earlier recorded draft to compare.\nCtrl-D: complete patch against parents\n\n"
				.. revision.description
		end
		return M.run({
			"evolog",
			"--revisions",
			revision.commit_id,
			"--limit",
			"1",
			"--no-graph",
			"--patch",
			"--git",
			"--template",
			draft_template,
		}, repo)
	end
	if path then
		return M.run({
			"diff",
			"--git",
			"-r",
			revision.commit_id,
			"--",
			literal_fileset(path),
		}, repo)
	end
	return M.run({ "show", "--git", revision.commit_id }, repo)
end

local function notify(err)
	vim.notify(err, vim.log.levels.WARN)
end

local function show_patch(content)
	local buffer = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(content, "\n", { plain = true }))
	vim.bo[buffer].bufhidden = "wipe"
	vim.bo[buffer].filetype = "git"
	vim.bo[buffer].modifiable = false
	vim.bo[buffer].readonly = true
	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, buffer)
end

local function display(text)
	return (text:match("^[^\r\n]*") or ""):gsub("[%c]", " ")
end

--- Opens a read-only picker with exact-entry lookup, not user text interpolated into commands.
---@param repo string
---@param evolution? string Revision to explore with evolog; absent selects stack history.
---@param path? string Exact root-relative file to inspect within workspace ancestry.
function M.pick(repo, evolution, path)
	local revisions, err = M.list(repo, evolution, path)
	if not revisions then
		notify(err)
		return
	end
	if #revisions == 0 then
		notify("No JJ history entries")
		return
	end
	local entries, lookup = {}, {}
	for index, revision in ipairs(revisions) do
		local entry = string.format(
			"%03d\t%s  %s  %s  %s",
			index,
			revision.change_id:sub(1, 12),
			revision.commit_id:sub(1, 12),
			display(table.concat(revision.bookmarks, " ")),
			display(revision.description)
		)
		if evolution then
			entry = string.format(
				"%03d\t%s  %s  %s  %s",
				index,
				index == 1 and "[selected]" or "[earlier]",
				display(revision.recorded_at or "time unavailable"),
				revision.commit_id:sub(1, 12),
				display(revision.description)
			)
		end
		entries[#entries + 1] = entry
		lookup[entry] = revision
	end
	local function selected_action(action)
		return function(selected)
			local revision = lookup[selected[1]]
			if revision then
				action(revision)
			end
		end
	end

	require("fzf-lua").fzf_exec(entries, {
		prompt = evolution and "Previous drafts> "
			or path and ("JJ file " .. display(path) .. "> ")
			or "JJ stack> ",
		fzf_opts = {
			["--delimiter"] = "\t",
			["--with-nth"] = "2..",
			["--no-sort"] = true,
			["--header"] = evolution and table.concat({
				"Previous drafts of this change",
				"Change: " .. revisions[1].change_id,
				"Enter: changes since earlier draft(s)",
				"Ctrl-D: complete patch against parents",
				"Ctrl-Y: copy change ID",
			}, "\n") or nil,
		},
		previewer = function()
			local class = require("fzf-lua.previewer.builtin").base:extend()
			function class:populate_preview_buf(entry)
				local revision = lookup[entry]
				if not revision then
					return
				end
				local content, preview_err
				if not evolution then
					content = revision.description
						.. "\n\nEnter: file overview (patches remain unloaded)\nCtrl-E: previous drafts of this change  Ctrl-Y: change ID"
				else
					content, preview_err = M.patch(repo, revision, evolution, path)
				end
				local buffer = self:get_tmp_buffer()
				vim.api.nvim_buf_set_lines(
					buffer,
					0,
					-1,
					false,
					vim.split(content or preview_err, "\n", { plain = true })
				)
				vim.bo[buffer].filetype = "git"
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
				[evolution and "ctrl-d" or "ctrl-e"] = selected_action(function(revision)
					if evolution then
						require("lib.jj_review").open(repo, revision, nil, true)
					else
						M.pick(repo, revision.commit_id)
					end
				end),
				["enter"] = selected_action(function(revision)
					if not evolution then
						require("lib.jj_review").open(repo, revision, path)
						return
					end
					local content, patch_err = M.patch(repo, revision, evolution, path)
					if content then
						show_patch(content)
					else
						notify(patch_err)
					end
				end),
				["ctrl-y"] = selected_action(function(revision)
					vim.fn.setreg("+", revision.change_id)
				end),
			}
		end,
	})
end

local function pick_current(evolution, file_history)
	local file = vim.api.nvim_buf_get_name(0)
	if file_history and (vim.bo.buftype ~= "" or file == "") then
		notify("JJ file history requires a named file buffer")
		return
	end
	local cwd = vim.bo.buftype == "" and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
	local repo, err = M.run({ "root" }, cwd)
	if not repo then
		notify(err)
		return
	end
	repo = repo:gsub("\n$", "")
	local path = file_history and vim.fs.relpath(repo, file) or nil
	if file_history and not path then
		notify("Current file is outside the JJ workspace")
		return
	end
	M.pick(repo, evolution, path)
end

--- Browses the current file's JJ repository, falling back to cwd for non-file buffers.
function M.pick_stack()
	pick_current()
end

--- Browses recorded modifications to the current path in @'s ancestry; does not follow renames.
function M.pick_file()
	pick_current(nil, true)
end

return M
