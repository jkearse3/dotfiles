local M = {}
local process = require("lib.jj_review_process")
local page = require("lib.jj_review_page")
local render = require("lib.jj_diff_render")
local sources = require("lib.jj_review_source")
local group = vim.api.nvim_create_augroup("JjLazyReview", { clear = true })

---@class lib.jj_review.File
---@field path string
---@field display string
---@field status string
---@field expanded? boolean
---@field spool? string
---@field job? lib.jj_review.Job
---@field error? string
---@field body? lib.jj_diff_render.Result
---@field positions? lib.jj_review.Position[]
---@field next? lib.jj_review.Position
---@field page? integer
---@field touched? integer

---@class lib.jj_review.Session
---@field buffer integer
---@field repo string
---@field revision lib.jj_history.Revision
---@field comparison lib.jj_review.Comparison
---@field files lib.jj_review.File[]
---@field jobs table<lib.jj_review.Job, boolean>
---@field rows integer[] File header rows, including collapsed files.
---@field rendered? lib.jj_diff_render.Result
---@field notice string
---@field description_expanded? boolean Shows the description body below its subject line.
---@field active boolean
---@field clock integer
---@field quickfix? integer
---@field jump_job? lib.jj_review.Job

---@type table<integer, lib.jj_review.Session>
local sessions = {}
local buffer_name = "jj-review://revision"
local patch_limit = 32 * 1024 * 1024
local metadata_limit = 2 * 1024 * 1024

local function text(value)
	return (value:gsub("[%c]", " "))
end

local fileset = sources.fileset

local function comparison_args(session)
	if session.comparison.from then
		return { "diff", "--from", session.comparison.from, "--to", session.revision.commit_id }
	end
	return { "diff", "-r", session.revision.commit_id }
end

local function unlink(path)
	if path then
		vim.uv.fs_unlink(path)
	end
end

local function drop(file)
	unlink(file.spool)
	file.spool, file.body, file.positions, file.next = nil, nil, nil, nil
end

local function cancel(session)
	session.jump_job = nil
	for job in pairs(session.jobs) do
		session.jobs[job] = nil
		job.cancel()
	end
	for _, file in ipairs(session.files) do
		if file.job then
			file.job = nil
			file.error = "Cancelled; collapse and expand to retry"
		end
	end
end

local function dispose(session)
	session.active = false
	cancel(session)
	for _, file in ipairs(session.files) do
		drop(file)
	end
	if session.quickfix then
		vim.fn.setqflist({}, "r", { id = session.quickfix, items = {} })
	end
end

local function file_at(session, row)
	for index = #session.rows, 1, -1 do
		if row >= session.rows[index] then
			return index
		end
	end
end

local function current_file(session)
	return file_at(session, vim.api.nvim_win_get_cursor(0)[1])
end

local function redraw(session)
	if not session.active or not vim.api.nvim_buf_is_valid(session.buffer) then
		return
	end
	local anchors = {}
	for _, window in ipairs(vim.fn.win_findbuf(session.buffer)) do
		local row = vim.api.nvim_win_get_cursor(window)[1]
		local index = file_at(session, row)
		anchors[window] = { index = index, offset = index and row - session.rows[index] or row - 1 }
	end
	local result = {
		lines = {},
		rows = {},
		quickfix = {},
		syntax_fragments = {},
		file_rows = {},
		hunk_rows = {},
	}
	local function append(item)
		local row = #result.lines + 1
		result.lines[row], result.rows[row] = item.text, item
		return row
	end
	append({
		kind = "metadata",
		text = "JJ "
			.. session.revision.change_id:sub(1, 12)
			.. " / "
			.. session.revision.commit_id:sub(1, 12)
			.. " vs "
			.. (session.comparison.from and session.comparison.from:sub(1, 12) or "parents")
			.. " · "
			.. text(session.comparison.title)
			.. (session.comparison.source.kind == "fixed" and " · pinned" or " · latest"),
	})
	if session.comparison.focus and session.comparison.focus.line then
		append({
			kind = "metadata",
			text = "Origin in this revision: "
				.. text(session.comparison.focus.path)
				.. ":"
				.. session.comparison.focus.line
				.. " — expand/page to inspect; header selected",
		})
	end
	local description = vim.split(vim.trim(session.revision.description), "\n", { plain = true })
	local has_body = #description > 1
	append({
		kind = "metadata",
		description_toggle = has_body,
		text = (has_body and (session.description_expanded and "[-] " or "[+] ") or "")
			.. (description[1] ~= "" and text(description[1]) or "(no description set)"),
	})
	if has_body and session.description_expanded then
		for index = 2, #description do
			if index > 20 then
				append({ kind = "metadata", text = "[description truncated]" })
				break
			end
			append({ kind = "metadata", text = text(description[index]) })
		end
	end
	append({ kind = "metadata", text = session.notice .. " — g?: keys" })
	session.rows = {}
	for index, file in ipairs(session.files) do
		local state = file.job and "loading"
			or file.error
			or file.spool and ("cached page " .. (file.page or 1))
			or "not loaded"
		local row = append({
			kind = "file",
			path = file.path,
			text = string.format(
				"[%s] %s %s  (%s)",
				file.expanded and "-" or "+",
				file.status,
				text(file.display),
				text(state)
			),
		})
		session.rows[index] = row
		result.file_rows[#result.file_rows + 1] = row
		result.quickfix[#result.quickfix + 1] = { lnum = row, text = text(file.display) }
		if file.expanded and file.body then
			local offset = #result.lines
			for _, item in ipairs(file.body.rows) do
				append(item)
			end
			for _, hunk in ipairs(file.body.hunk_rows) do
				result.hunk_rows[#result.hunk_rows + 1] = hunk + offset
				result.quickfix[#result.quickfix + 1] =
					{ lnum = hunk + offset, text = text(file.path) .. " (hunk)" }
			end
			for _, fragment in ipairs(file.body.syntax_fragments) do
				local rows = {}
				for source, target in pairs(fragment.rows) do
					rows[source] = target + offset
				end
				result.syntax_fragments[#result.syntax_fragments + 1] =
					{ path = fragment.path, lines = fragment.lines, rows = rows }
			end
			append({
				kind = "metadata",
				text = "  Page "
					.. file.page
					.. (file.next and " — ]p: next page" or " — end of patch")
					.. (file.page > 1 and " — [p: previous page" or ""),
			})
		end
	end
	vim.bo[session.buffer].readonly = false
	vim.bo[session.buffer].modifiable = true
	vim.api.nvim_buf_set_lines(session.buffer, 0, -1, false, result.lines)
	vim.bo[session.buffer].modifiable = false
	vim.bo[session.buffer].readonly = true
	session.rendered = result
	render.decorate(session.buffer, result)
	render.set_review_state(
		session.buffer,
		"Pinned JJ review: " .. text(session.comparison.title),
		"fresh"
	)
	local items = {}
	for _, item in ipairs(result.quickfix) do
		items[#items + 1] = { bufnr = session.buffer, lnum = item.lnum, text = item.text }
	end
	local list = session.quickfix and vim.fn.getqflist({ id = session.quickfix, nr = 0 })
	if list and list.id == session.quickfix then
		vim.fn.setqflist(
			{},
			"r",
			{ id = session.quickfix, title = text(session.comparison.title), items = items }
		)
		if vim.api.nvim_get_current_buf() == session.buffer then
			vim.cmd("silent chistory " .. list.nr)
		end
	else
		vim.fn.setqflist({}, " ", { title = text(session.comparison.title), items = items })
		session.quickfix = vim.fn.getqflist({ id = 0 }).id
	end
	for window, anchor in pairs(anchors) do
		local start = anchor.index and session.rows[anchor.index] or 1
		local last = anchor.index
				and session.rows[anchor.index + 1]
				and session.rows[anchor.index + 1] - 1
			or #result.lines
		vim.api.nvim_win_set_cursor(window, { math.min((start or 1) + anchor.offset, last), 0 })
	end
end

local function capture(session, args, callback, limit)
	local job
	job = process.start(session.repo, args, limit or metadata_limit, function(err)
		local live = session.active and session.jobs[job]
		session.jobs[job] = nil
		local output, read_err
		if live and not err then
			output, read_err = process.read(job.path, limit or metadata_limit)
		end
		unlink(job.path)
		if live then
			callback(output, err or read_err)
		end
	end)
	session.jobs[job] = true
	return job
end

local function load_files(session)
	local template =
		'"{\\"path\\":" ++ stringify(path).escape_json() ++ ",\\"display\\":" ++ display_diff_path.escape_json() ++ ",\\"status\\":" ++ status_char.escape_json() ++ "}\\n"'
	local args = comparison_args(session)
	vim.list_extend(args, { "-T", template })
	capture(session, args, function(output, err)
		if err then
			session.notice = text(err)
			redraw(session)
			return
		end
		local files = {}
		for line in output:gmatch("[^\r\n]+") do
			local ok, file = pcall(vim.json.decode, line)
			if
				not ok
				or type(file) ~= "table"
				or type(file.path) ~= "string"
				or type(file.display) ~= "string"
				or type(file.status) ~= "string"
				or #files >= 10000
			then
				session.notice = "Invalid or oversized JJ file overview"
				redraw(session)
				return
			end
			files[#files + 1] = file
		end
		session.files = files
		session.notice = #files .. " changed files — patches load only when explicitly expanded"
		redraw(session)
		if vim.api.nvim_get_current_buf() ~= session.buffer then
			return
		end

		local focus = session.comparison.focus
		if focus then
			for index, file in ipairs(files) do
				if file.path == focus.path then
					vim.api.nvim_win_set_cursor(0, { session.rows[index], 0 })
					return
				end
			end
			session.notice = session.notice .. " — selected path is not in this comparison"
			redraw(session)
		end

		-- Without a matching focus path, land on the file list rather than the revision header.
		if session.rows[1] then
			vim.api.nvim_win_set_cursor(0, { session.rows[1], 0 })
		end
	end)
end

local function read_page(session, file, number)
	local body, next_position, err =
		page.read(file.spool, file.path, file.status == "D", file.positions[number])
	if err then
		file.error = err
	else
		session.clock = session.clock + 1
		file.touched = session.clock
		file.body, file.next, file.page, file.error = body, next_position, number, nil
		if next_position then
			file.positions[number + 1] = next_position
		end
	end
	redraw(session)
end

local function make_room(session, selected)
	session.clock = session.clock + 1
	selected.touched = session.clock
	local expanded, cached = {}, {}
	for _, file in ipairs(session.files) do
		if file ~= selected then
			if file.expanded then
				expanded[#expanded + 1] = file
			end
			if file.spool or file.job then
				cached[#cached + 1] = file
			end
		end
	end
	local function oldest(a, b)
		return (a.touched or 0) < (b.touched or 0)
	end
	table.sort(expanded, oldest)
	table.sort(cached, oldest)
	for index = 1, math.max(0, #expanded - 7) do
		local file = expanded[index]
		file.expanded = false
		if file.job then
			session.jobs[file.job] = nil
			file.job.cancel()
			file.job = nil
		end
	end
	for index = 1, math.max(0, #cached - 15) do
		local file = cached[index]
		file.expanded = false
		if file.job then
			session.jobs[file.job] = nil
			file.job.cancel()
			file.job = nil
		end
		drop(file)
	end
end

--- Toggles a file's patch explicitly. Navigation alone never calls this method.
---@param buffer integer
function M.toggle(buffer)
	local session = sessions[buffer]
	if not session then
		return
	end
	local row = session.rendered.rows[vim.api.nvim_win_get_cursor(0)[1]]
	if row and row.description_toggle then
		session.description_expanded = not session.description_expanded
		redraw(session)
		return
	end
	local index = current_file(session)
	local file = index and session.files[index]
	if not file then
		return
	end
	if file.expanded then
		file.expanded = false
		if file.job then
			session.jobs[file.job] = nil
			file.job.cancel()
			file.job = nil
		end
		redraw(session)
		return
	end
	make_room(session, file)
	file.expanded, file.error = true, nil
	if file.spool then
		read_page(session, file, file.page or 1)
		return
	end
	local args = { "--config", "diff.git.show-path-prefix=true" }
	vim.list_extend(args, comparison_args(session))
	vim.list_extend(args, { "--git", "--", fileset(file.path) })
	local job
	job = process.start(session.repo, args, patch_limit, function(err)
		local live = session.active and session.jobs[job] and file.job == job
		session.jobs[job] = nil
		if not live then
			unlink(job.path)
			return
		end
		file.job = nil
		if err then
			unlink(job.path)
			file.error = text(err)
			redraw(session)
			return
		end
		file.spool = job.path
		file.positions = { { offset = 0, old = 0, new = 0, hunk = false } }
		read_page(session, file, 1)
	end)
	file.job = job
	session.jobs[job] = true
	redraw(session)
end

--- Changes only the selected expanded file's bounded page; never expands another file.
---@param buffer integer
---@param direction integer
function M.turn_page(buffer, direction)
	local session = sessions[buffer]
	local index = session and current_file(session)
	local file = index and session.files[index]
	if not file or not file.expanded or not file.spool then
		return
	end
	local number = (file.page or 1) + direction
	if number < 1 or not file.positions[number] then
		return
	end
	read_page(session, file, number)
	vim.api.nvim_win_set_cursor(0, { session.rows[index], 0 })
end

--- Cancels active requests, retaining completed cached pages.
---@param buffer integer
function M.cancel(buffer)
	sources.cancel_pending()
	local session = sessions[buffer or vim.fn.bufnr(buffer_name)]
	if session then
		cancel(session)
		session.notice = "Requests cancelled — R refreshes the overview"
		redraw(session)
	end
end

--- Resolves the latest source transactionally. Failed resolution preserves the pinned view/cache.
---@param buffer integer
function M.refresh(buffer)
	local session = sessions[buffer]
	if not session then
		return
	end
	cancel(session)
	session.notice = "Resolving review source…"
	redraw(session)
	local job
	job = sources.start(session.repo, session.comparison.source, function(comparison, err)
		if not session.active or not session.jobs[job] then
			return
		end
		session.jobs[job] = nil
		if err then
			session.notice = "Refresh failed; retained pinned comparison: " .. text(err)
			redraw(session)
			return
		end
		-- Requests launched against the old comparison while resolution was in flight are stale.
		cancel(session)
		for _, file in ipairs(session.files) do
			drop(file)
		end
		if session.comparison.focus then
			comparison.focus = { path = session.comparison.focus.path }
		end
		session.comparison, session.revision = comparison, comparison.revision
		session.files, session.rows = {}, {}
		session.notice = "Loading changed-file overview…"
		redraw(session)
		load_files(session)
	end)
	session.jobs[job] = true
end

local working_file_error = sources.file_error

local function working_line(session)
	local row = session.rendered.rows[vim.api.nvim_win_get_cursor(0)[1]]
	if not row or not row.location then
		vim.notify("Select a surviving source line", vim.log.levels.WARN)
		return
	end
	local location = row.location
	if session.jump_job then
		session.jobs[session.jump_job] = nil
		session.jump_job.cancel()
	end
	local function request(args, callback)
		session.jump_job = capture(session, args, function(output, err)
			session.jump_job = nil
			if err then
				vim.notify(err, vim.log.levels.WARN)
				return
			end
			if vim.api.nvim_get_current_buf() == session.buffer then
				callback(output)
			end
		end, 1024 * 1024)
	end
	-- Pin @ once so mapping and validation agree across concurrent JJ operations.
	-- Never jump using unsnapshotted or stale buffer contents.
	request({ "log", "--no-graph", "-r", "@", "-T", "commit_id" }, function(commit)
		commit = vim.trim(commit)
		if not commit:match("^%x+$") then
			vim.notify("Invalid JJ working snapshot", vim.log.levels.WARN)
			return
		end
		request({
			"--config",
			"diff.git.show-path-prefix=true",
			"diff",
			"--git",
			"--from",
			session.revision.commit_id,
			"--to",
			commit,
		}, function(patch)
			local diff = require("lib.jj_diff")
			local path, line = diff.map_line(patch, location.path, location.line)
			if not path then
				vim.notify("Patch line does not survive in the working copy", vim.log.levels.WARN)
				return
			end
			request(
				{ "file", "show", "-r", commit, "-T", '""', "--", fileset(path) },
				function(expected)
					local err = working_file_error(session.repo, path, expected)
					if err then
						vim.notify(err, vim.log.levels.WARN)
						return
					end
					local absolute = vim.fs.joinpath(session.repo, path)
					local stat = vim.uv.fs_stat(absolute)
					if not stat or stat.type ~= "file" then
						vim.notify(
							"Working-copy file does not exist: " .. path,
							vim.log.levels.WARN
						)
						return
					end
					local buffer = vim.fn.bufadd(absolute)
					vim.fn.bufload(buffer)
					-- Loading may run hooks that change the buffer after the first verification.
					err = working_file_error(session.repo, path, expected)
					if err then
						vim.notify(err, vim.log.levels.WARN)
						return
					end
					if line > vim.api.nvim_buf_line_count(buffer) then
						vim.notify(
							"Mapped line is outside the working-copy file",
							vim.log.levels.WARN
						)
						return
					end
					vim.cmd.edit(vim.fn.fnameescape(absolute))
					vim.api.nvim_win_set_cursor(0, { line, 0 })
				end
			)
		end)
	end)
end

--- Jumps to a file header without expanding it or requesting a patch.
---@param buffer integer
function M.pick_file(buffer)
	local session = sessions[buffer]
	if not session then
		return
	end
	vim.ui.select(session.files, {
		prompt = "JJ review file",
		format_item = function(file)
			return text(file.display)
		end,
	}, function(file)
		if not file or not session.active then
			return
		end
		for index, candidate in ipairs(session.files) do
			if candidate == file and vim.api.nvim_get_current_buf() == buffer then
				vim.api.nvim_win_set_cursor(0, { session.rows[index], 0 })
				return
			end
		end
	end)
end

--- Lists the review buffer's key mappings in a float that closes when the cursor moves.
---@param buffer integer
function M.show_keys(buffer)
	local lines = {}
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do
		local description = mapping.desc and mapping.desc:match("^JJ review: (.+)")
		if description then
			lines[#lines + 1] = string.format("%-6s %s", mapping.lhs, description)
		end
	end
	table.sort(lines)
	vim.lsp.util.open_floating_preview(
		lines,
		"",
		{ border = "rounded", title = " JJ review keys " }
	)
end

--- Opens a revision against its parents; optional path focuses a header without loading its patch.
--- Fixed drafts reload the same commit on R; normal revisions follow the change's latest version.
---@param repo string
---@param revision lib.jj_history.Revision
---@param path? string Root-relative path to focus.
---@param fixed? boolean Keep an exact historical draft pinned across refresh.
---@return integer buffer
function M.open(repo, revision, path, fixed)
	return M.open_comparison(repo, {
		revision = revision,
		title = fixed and "Pinned draft against parents" or "Revision against parents",
		source = {
			kind = fixed and "fixed" or "revision",
			name = fixed and revision.commit_id or revision.change_id,
		},
		focus = path and { path = path } or nil,
	})
end

--- Opens/replaces the shared overview for immutable comparison endpoints. Only metadata loads.
--- Expansion, pages, cache and callbacks belong to this session, regardless of its entry point.
---@param repo string
---@param comparison lib.jj_review.Comparison
---@return integer buffer
function M.open_comparison(repo, comparison)
	sources.cancel_pending()
	local buffer = vim.fn.bufnr(buffer_name)
	if buffer < 0 then
		buffer = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_set_name(buffer, buffer_name)
	end
	if sessions[buffer] then
		dispose(sessions[buffer])
	end
	local session = {
		buffer = buffer,
		repo = repo,
		revision = vim.deepcopy(comparison.revision),
		comparison = vim.deepcopy(comparison),
		files = {},
		jobs = {},
		rows = {},
		notice = "Loading changed-file overview…",
		active = true,
		clock = 0,
	}
	sessions[buffer] = session
	vim.bo[buffer].buftype = "nofile"
	vim.bo[buffer].bufhidden = "hide"
	vim.bo[buffer].swapfile = false
	vim.bo[buffer].readonly = true
	vim.bo[buffer].filetype = "jjdiff"
	render.prepare_window(vim.api.nvim_get_current_win(), buffer)
	vim.api.nvim_win_set_buf(0, buffer)
	local function map(key, action, description)
		vim.keymap.set("n", key, action, { buffer = buffer, desc = "JJ review: " .. description })
	end
	map("<CR>", function()
		M.toggle(buffer)
	end, "Expand/collapse file or description")
	map("]f", function()
		render.navigate_file(1)
	end, "Next file header")
	map("[f", function()
		render.navigate_file(-1)
	end, "Previous file header")
	map("]c", function()
		render.navigate_hunk(1)
	end, "Next loaded hunk")
	map("[c", function()
		render.navigate_hunk(-1)
	end, "Previous loaded hunk")
	map("]p", function()
		M.turn_page(buffer, 1)
	end, "Next patch page")
	map("[p", function()
		M.turn_page(buffer, -1)
	end, "Previous patch page")
	map("x", function()
		M.cancel(buffer)
	end, "Cancel requests")
	map("R", function()
		M.refresh(buffer)
	end, "Refresh and clear cache (pinned: same version; latest: newest source)")
	map("f", function()
		M.pick_file(buffer)
	end, "Find file header")
	map("gf", function()
		working_line(session)
	end, "Open working-copy line")
	map("g?", function()
		M.show_keys(buffer)
	end, "Show keys")
	vim.api.nvim_clear_autocmds({ group = group, buffer = buffer })
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		buffer = buffer,
		once = true,
		callback = function()
			dispose(session)
			sessions[buffer] = nil
		end,
	})
	redraw(session)
	load_files(session)
	return buffer
end

--- Returns to the retained review without resolving sources, refreshing, or loading any patches.
function M.resume()
	local buffer = vim.fn.bufnr(buffer_name)
	if not sessions[buffer] then
		vim.notify("No retained JJ review; use jl, jb, jf, or ja first", vim.log.levels.INFO)
		return
	end
	render.prepare_window(vim.api.nvim_get_current_win(), buffer)
	vim.api.nvim_win_set_buf(0, buffer)
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	callback = function()
		for _, session in pairs(sessions) do
			dispose(session)
		end
	end,
})

return M
