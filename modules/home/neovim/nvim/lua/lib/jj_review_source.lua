local M = {}
local process = require("lib.jj_review_process")
local diff = require("lib.jj_diff")

---@class lib.jj_review.Source
---@field kind "revision"|"fixed"|"bookmark"|"line"|"bookmarks"|"file-history"
---@field name? string Full change ID, exact commit ID, or local bookmark name.
---@field path? string Root-relative path for line attribution or file history.
---@field line? integer One-based recorded working-file line.

---@class lib.jj_review.Focus
---@field path string Root-relative historical path.
---@field line? integer Informational source line; file starts collapsed.

---@class lib.jj_review.Comparison
---@field revision lib.jj_history.Revision Immutable target snapshot.
---@field from? string Immutable base snapshot; absent means target's parents.
---@field title string Human-readable comparison, including the base policy.
---@field source lib.jj_review.Source Identity resolved on explicit refresh.
---@field focus? lib.jj_review.Focus File header to focus without loading its patch.

--- Encodes an exact root-relative fileset, including control bytes and metacharacters.
---@param path string
---@return string
function M.fileset(path)
	return 'root-file:"'
		.. path:gsub('[\\"%c]', function(char)
			return string.format("\\x%02x", char:byte())
		end)
		.. '"'
end

--- Refuses navigation/attribution unless disk and every loaded alias match a recorded blob.
--- Byte reads are bounded to 1 MiB; DOS line endings and UTF-8 BOMs are normalized for buffers.
---@param repo string
---@param path string
---@param expected string Recorded file bytes.
---@return string? error
function M.file_error(repo, path, expected)
	local absolute = vim.fs.joinpath(repo, path)
	local disk, err = process.read(absolute, 1024 * 1024 + 1)
	if not disk then
		return err
	end
	if disk ~= expected then
		return "Working file differs from recorded JJ snapshot; record changes before inspecting this line"
	end
	local real = vim.uv.fs_realpath(absolute) or absolute
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buffer)
		if vim.api.nvim_buf_is_loaded(buffer) and (vim.uv.fs_realpath(name) or name) == real then
			if vim.bo[buffer].modified or vim.bo[buffer].buftype ~= "" then
				return "Working-copy buffer has unsaved changes or is not a file"
			end
			if
				vim.api.nvim_buf_get_offset(buffer, vim.api.nvim_buf_line_count(buffer))
				> 1024 * 1024 + 1
			then
				return "Working-copy buffer exceeds the 1 MiB verification limit"
			end
			local contents = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
			if vim.bo[buffer].endofline then
				contents = contents .. "\n"
			end
			local normalized = expected
			if vim.bo[buffer].bomb and normalized:sub(1, 3) == "\239\187\191" then
				normalized = normalized:sub(4)
			end
			if vim.bo[buffer].fileformat == "dos" then
				normalized = normalized:gsub("\r\n", "\n")
			end
			if contents ~= normalized then
				return "Buffer differs from recorded JJ snapshot; save/record or reload before inspecting this line"
			end
		end
	end
end

local function revision(run, revset)
	local output, err = run({ "log", "--no-graph", "-r", revset, "-T", 'json(self) ++ "\\n"' })
	if not output then
		return nil, err
	end
	local ok, value = pcall(vim.json.decode, output)
	if
		not ok
		or type(value) ~= "table"
		or type(value.commit_id) ~= "string"
		or not value.commit_id:match("^%x+$")
		or type(value.change_id) ~= "string"
		or not value.change_id:match("^[a-z]+$")
		or type(value.description) ~= "string"
	then
		return nil, "Source no longer resolves to exactly one JJ revision"
	end
	return value
end

local function resolve(repo, source, run)
	if source.kind == "file-history" then
		return require("lib.jj_file_history").trace(source.path, run)
	end
	if source.kind == "bookmarks" then
		return diff.list_bookmarks(repo, run)
	end
	if source.kind == "bookmark" then
		local bookmarks, err = diff.list_bookmarks(repo, run)
		if not bookmarks then
			return nil, err
		end
		local selected
		for _, bookmark in ipairs(bookmarks) do
			if bookmark.name == source.name then
				selected = bookmark
				break
			end
		end
		if not selected then
			return nil, "Local bookmark no longer exists: " .. source.name
		end
		local range
		range, err = diff.bookmark_comparison(repo, selected, bookmarks, run)
		if not range then
			return nil, err
		end
		local target
		target, err = revision(run, range.target)
		if not target then
			return nil, err
		end
		return {
			revision = target,
			from = range.from,
			title = range.title .. " (nearest first-parent bookmark)",
			source = source,
		}
	end
	if source.kind == "line" then
		local working, err = revision(run, "@")
		if not working then
			return nil, err
		end
		local expected
		expected, err = run({
			"file",
			"show",
			"-r",
			working.commit_id,
			"-T",
			'""',
			"--",
			M.fileset(source.path),
		})
		if not expected then
			return nil, err
		end
		err = M.file_error(repo, source.path, expected)
		if err then
			return nil, err
		end
		local function pinned(args)
			args = vim.deepcopy(args)
			for index, arg in ipairs(args) do
				if arg == "@" and (args[index - 1] == "-r" or args[index - 1] == "--to") then
					args[index] = working.commit_id
				end
			end
			return run(args)
		end
		local comparison, location =
			diff.resolve_line_revision(repo, source.path, source.line, pinned)
		if not comparison then
			return nil, location
		end
		local target
		target, err = revision(run, comparison.target)
		if not target then
			return nil, err
		end
		err = M.file_error(repo, source.path, expected)
		if err then
			return nil, err
		end
		return {
			revision = target,
			title = "Line origin: "
				.. source.path
				.. ":"
				.. source.line
				.. " — revision against parents",
			source = { kind = "revision", name = target.change_id },
			focus = location,
		}
	end
	local revset = source.name
	if source.kind == "revision" then
		if not revset or not revset:match("^[a-z]+$") then
			return nil, "Invalid JJ change identity"
		end
		revset = "change_id(" .. revset .. ")"
	elseif source.kind ~= "fixed" or not revset or not revset:match("^%x+$") then
		return nil, "Invalid JJ review source"
	end
	local target, err = revision(run, revset)
	if not target then
		return nil, err
	end
	return {
		revision = target,
		title = source.kind == "fixed" and "Pinned draft against parents"
			or "Revision against parents",
		source = source,
	}
end

--- Resolves a review source asynchronously at ONE recorded operation, without snapshot/import.
--- Cancellation suppresses completion and deletes active output. Resolution is transactional:
--- callers decide whether to replace their view only after a complete successful result.
--- Metadata is capped at 2 MiB; file verification and each line-analysis patch at 1 MiB.
---@param repo string
---@param source lib.jj_review.Source
---@param complete fun(result: lib.jj_review.Comparison|lib.jj_file_history.Result|table[]|nil, error: string?)
---@return lib.jj_review.Job request
function M.start(repo, source, complete)
	local active, job, operation = true, nil, nil
	local request = {
		cancel = function()
			active = false
			if job then
				job.cancel()
			end
		end,
	}
	local function capture(args, callback)
		local limit = (vim.tbl_contains(args, "--git") or args[1] == "file" and args[2] == "show")
				and 1024 * 1024
			or 2 * 1024 * 1024
		local current
		current = process.start(repo, args, limit, function(err)
			local output, read_err
			if active and not err then
				output, read_err = process.read(current.path, limit)
			end
			if current.path then
				vim.uv.fs_unlink(current.path)
			end
			if active then
				if source.kind == "line" and err == "JJ output exceeded the cache limit" then
					if vim.tbl_contains(args, "--git") then
						err = "JJ line-origin file patch exceeds the 1 MiB analysis limit"
					elseif args[1] == "file" and args[2] == "show" then
						err = "JJ line-origin file exceeds the 1 MiB verification limit"
					end
				end
				callback(output, err or read_err)
			end
		end, operation)
		job = current
	end
	capture({ "op", "log", "--no-graph", "--limit", "1", "-T", "id" }, function(output, err)
		operation = vim.trim(output or "")
		if err or not operation:match("^%x+$") then
			active = false
			complete(nil, err or "Cannot pin JJ operation")
			return
		end
		local thread = coroutine.create(function()
			return resolve(repo, source, function(args)
				return coroutine.yield(args)
			end)
		end)
		local function step(...)
			local ok, value, failure = coroutine.resume(thread, ...)
			if not ok or coroutine.status(thread) == "dead" then
				active = false
				if not ok then
					complete(nil, tostring(value))
				else
					complete(value, failure)
				end
			else
				capture(value, step)
			end
		end
		step()
	end)
	return request
end

local pending

--- Cancels source selection/line attribution before a review opens; leaves the current view intact.
function M.cancel_pending()
	if pending then
		pending.cancel()
		pending = nil
	end
end

local function root()
	local file = vim.api.nvim_buf_get_name(0)
	local cwd = vim.bo.buftype == "" and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
	local repo, err = require("lib.jj_history").run({ "root" }, cwd)
	if not repo then
		vim.notify(
			(err or "JJ repository unavailable") .. "\nGit alternatives: glh / glf / gbl / gbf",
			vim.log.levels.WARN
		)
		return
	end
	return vim.trim(repo)
end

local function inspect(repo, source, callback)
	M.cancel_pending()
	local buffer, window = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	local tick = vim.api.nvim_buf_get_changedtick(buffer)
	pending = M.start(repo, source, function(result, err)
		pending = nil
		if
			vim.api.nvim_get_current_buf() ~= buffer
			or vim.api.nvim_get_current_win() ~= window
			or not vim.api.nvim_buf_is_valid(buffer)
			or vim.api.nvim_buf_get_changedtick(buffer) ~= tick
		then
			return
		end
		if err then
			vim.notify(err, vim.log.levels.WARN)
			return
		end
		callback(result)
	end)
end

--- Looks up renamed file history with the same cancellation and initiating-buffer guards as ja.
---@param repo string
---@param path string Recorded root-relative file path.
---@param callback fun(result: lib.jj_file_history.Result)
function M.inspect_file_history(repo, path, callback)
	inspect(repo, { kind = "file-history", path = path }, callback)
end

--- Selects a local bookmark, then opens its first-parent bookmark range in the shared overview.
function M.pick_bookmark()
	local repo = root()
	if not repo then
		return
	end
	inspect(repo, { kind = "bookmarks" }, function(bookmarks)
		local entries, lookup = {}, {}
		for index, bookmark in ipairs(bookmarks) do
			local entry = string.format("%03d\t%s", index, bookmark.display)
			entries[#entries + 1], lookup[entry] = entry, bookmark
		end
		if #entries == 0 then
			vim.notify("No local JJ bookmarks", vim.log.levels.INFO)
			return
		end
		require("fzf-lua").fzf_exec(entries, {
			prompt = "JJ bookmark range> ",
			fzf_opts = {
				["--delimiter"] = "\t",
				["--with-nth"] = "2..",
				["--header"] = "Nearest older first-parent bookmark -> selected bookmark\nEnter: file overview (no patches loaded)",
			},
			actions = function()
				return {
					enter = function(selected)
						local bookmark = lookup[selected[1]]
						if not bookmark then
							return
						end
						vim.schedule(function()
							inspect(
								repo,
								{ kind = "bookmark", name = bookmark.name },
								function(comparison)
									require("lib.jj_review").open_comparison(repo, comparison)
								end
							)
						end)
					end,
				}
			end,
		})
	end)
end

--- Inspects the recorded origin of the current source line, focusing its historical file header.
--- Unsaved/unrecorded/stale text is refused rather than snapshotted or attributed at wrong offsets.
function M.open_line()
	local buffer = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(buffer)
	if vim.bo[buffer].buftype ~= "" or file == "" or vim.bo[buffer].modified then
		vim.notify("JJ line origin requires a saved, named file buffer", vim.log.levels.WARN)
		return
	end
	local repo = root()
	if not repo then
		return
	end
	local path = vim.fs.relpath(vim.uv.fs_realpath(repo) or repo, vim.uv.fs_realpath(file) or file)
	if not path then
		vim.notify("File is outside the JJ workspace", vim.log.levels.WARN)
		return
	end
	inspect(
		repo,
		{ kind = "line", path = path, line = vim.api.nvim_win_get_cursor(0)[1] },
		function(comparison)
			require("lib.jj_review").open_comparison(repo, comparison)
		end
	)
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("JjReviewSources", { clear = true }),
	callback = M.cancel_pending,
})

return M
