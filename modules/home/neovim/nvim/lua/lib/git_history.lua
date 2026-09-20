local M = {}

--- Opens the selected commit as a disposable, read-only patch rather than checking it out.
---@param selected string[]
---@param opts table Normalized fzf-lua options, including cwd and optional rename-following parser.
function M.show_commit(selected, opts)
	if not selected[1] then
		return
	end
	local commit = opts.fn_match_commit_hash and opts.fn_match_commit_hash(selected[1], opts)
		or selected[1]:match("^(%x+)")
	if not commit or not commit:match("^%x+$") then
		vim.notify("Cannot identify the selected Git commit", vim.log.levels.ERROR)
		return
	end

	local result = vim.system({
		"git",
		"--no-pager",
		"show",
		"--no-ext-diff",
		"--no-textconv",
		"--format=fuller",
		"--stat",
		"--patch",
		commit,
		"--",
	}, {
		cwd = opts.cwd,
		text = true,
	}):wait()
	if result.code ~= 0 then
		vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
		return
	end

	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result.stdout, "\n", { plain = true }))
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "git"
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, buf)
end

--- Decodes fzf-lua's rename-following path field, which Git may C-quote.
---@param entry string
---@param opts table
---@return string
local function followed_path(entry, opts)
	local path = entry:match("^[^\t]+\t([^\t]+)")
	if not path then
		return assert(vim.fs.relpath(opts.cwd, vim.api.nvim_buf_get_name(0)))
	end
	if path:sub(1, 1) ~= '"' then
		return path
	end

	local escapes = {
		a = "\a",
		b = "\b",
		t = "\t",
		n = "\n",
		v = "\v",
		f = "\f",
		r = "\r",
	}
	local decoded, index = {}, 2
	while index < #path do
		local char = path:sub(index, index)
		index = index + 1
		if char == "\\" then
			local octal = path:sub(index):match("^[0-7][0-7][0-7]")
			char = path:sub(index, index)
			index = index + (octal and 3 or 1)
			char = octal and string.char(tonumber(octal, 8)) or escapes[char] or char
		end
		decoded[#decoded + 1] = char
	end
	return table.concat(decoded)
end

--- Uses argv rather than fzf's printed path field for rename-following previews.
local function file_previewer()
	local class = require("fzf-lua.previewer.builtin").base:extend()
	function class:populate_preview_buf(entry)
		local commit = entry:match("^(%x+)")
		local path = entry:find("\t", 1, true) and followed_path(entry, self.opts)
			or vim.fs.relpath(self.opts.cwd, vim.api.nvim_buf_get_name(self.win.src_bufnr))
		local result = vim.system({
			"git",
			"--literal-pathspecs",
			"show",
			"--no-ext-diff",
			"--no-textconv",
			"--format=fuller",
			commit,
			"--",
			path,
		}, {
			cwd = self.opts.cwd,
			text = true,
		}):wait()
		local buffer = self:get_tmp_buffer()
		local content = result.code == 0 and result.stdout or result.stderr
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(content, "\n", { plain = true }))
		vim.bo[buffer].filetype = "git"
		self:set_preview_buf(buffer)
	end
	return {
		_ctor = function()
			return class
		end,
	}
end

--- Supplies complete action allowlists, not additions to fzf-lua's checkout defaults.
--- Applies to direct :FzfLua calls as well as the mapped history pickers.
---@param fzf fzf-lua
---@return table
function M.options(fzf)
	-- Functions replace provider defaults; plain tables would be deep-merged.
	local commit_actions = {
		["enter"] = M.show_commit,
		["ctrl-y"] = fzf.actions.git_yank_commit,
	}
	return {
		commits = {
			actions = function()
				return vim.deepcopy(commit_actions)
			end,
		},
		reflog = {
			actions = function()
				return vim.deepcopy(commit_actions)
			end,
		},
		bcommits = {
			follow = true,
			fn_match_file = followed_path,
			previewer = file_previewer,
			actions = function()
				return {
					["enter"] = fzf.actions.git_buf_edit,
					["ctrl-s"] = fzf.actions.git_buf_split,
					["ctrl-v"] = fzf.actions.git_buf_vsplit,
					["ctrl-t"] = fzf.actions.git_buf_tabedit,
					["ctrl-d"] = M.show_commit,
					["ctrl-y"] = fzf.actions.git_yank_commit,
				}
			end,
		},
	}
end

--- Finds the current file's repository; unnamed buffers fall back to the editor cwd.
---@return string|nil
local function repository_directory()
	local file = vim.api.nvim_buf_get_name(0)
	local cwd = vim.bo.buftype == "" and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
	local result = vim.system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" }, {
		text = true,
	}):wait()
	if result.code ~= 0 then
		vim.notify("Current buffer is not in a Git repository", vim.log.levels.WARN)
		return
	end
	return vim.trim(result.stdout)
end

--- Browses repository history with patch inspection on Enter and SHA copying on Ctrl-Y.
function M.pick_repository()
	local cwd = repository_directory()
	if cwd then
		require("fzf-lua").git_commits({ cwd = cwd })
	end
end

--- Browses file history across renames; Enter opens historical contents, Ctrl-D the commit.
function M.pick_file()
	if vim.bo.buftype ~= "" or vim.api.nvim_buf_get_name(0) == "" then
		vim.notify("File history requires a named file buffer", vim.log.levels.WARN)
		return
	end
	local cwd = repository_directory()
	if cwd then
		require("fzf-lua").git_bcommits({ cwd = cwd })
	end
end

return M
